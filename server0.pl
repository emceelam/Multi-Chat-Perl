#!/usr/bin/env perl

use warnings;
use strict;
use Socket qw(:DEFAULT :crlf);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use POSIX;
use Readonly;
use List::Util qw(min);
use autodie qw(:socket fcntl sysread syswrite);
use Data::Dumper;


Readonly my $PORT => 4020;
Readonly my $TIME_OUT => 10;


print <<TEXT
Multi client chat server, using telnet, programmed in C
To connect:
    telnet 127.0.0.1 $PORT

Everything typed by one chat user will be copied to other chat users.
Typing 'quit' on telnet sessions will disconnect.
TEXT
;

my $listen_handle;
socket($listen_handle, AF_INET, SOCK_STREAM, 0);

setsockopt($listen_handle, SOL_SOCKET, SO_REUSEADDR, pack("l", 1));

my $sockaddr = pack_sockaddr_in ($PORT, INADDR_ANY);
bind ($listen_handle, $sockaddr);

my $backlog = 5;
listen ($listen_handle, $backlog);

my %fd_to_handle;
my $listen_fd = fileno($listen_handle);
$fd_to_handle{$listen_fd} = $listen_handle;


my $save_set = "";
my $rbits;
vec($save_set, $listen_fd, 1) = 1;
my $loop_cnt = 0;
my %fd_to_expiry;
my $max_fd;
while (1) {
  # print "rin: " . unpack ("H*", $save_set) . "\n";
  $rbits = $save_set;

  # select RBITS,WBITS,EBITS,TIMEOUT
  select ($rbits, undef, undef, $TIME_OUT);

  $max_fd = length unpack ("B*", $rbits);
  my $now = time();
  if (vec($rbits, $listen_fd, 1)) {
    my $conn_handle;
    my $paddr = accept ($conn_handle, $listen_handle);
    my ($port, $iaddr) = sockaddr_in($paddr);
    my $name = gethostbyaddr($iaddr, AF_INET);
    my $conn_fd = fileno($conn_handle);
    $fd_to_handle{$conn_fd} = $conn_handle;
    $fd_to_expiry{$conn_fd} = $now + $TIME_OUT;
    vec($save_set, $conn_fd, 1) = 1;
    print ("accepted conn $conn_fd from $name, $port\n");

    my $packed = pack("l l", 0, 1);
    #print "SO_LINGER packed: " . unpack ("H*", $packed) . "\n";
    setsockopt($conn_handle, SOL_SOCKET, SO_LINGER, $packed);

    my $flags = fcntl($conn_handle, F_GETFL, 0);
    fcntl($conn_handle, F_SETFL, $flags | O_NONBLOCK);
  }

  foreach my $read_fd ( ($listen_fd+1)..$max_fd) {
    if (!vec ($rbits, $read_fd, 1)) {
      next;
    }
    print "socket fd $read_fd is readable\n";
  
    my $buf = pack ("C80",0);
    my $handle = $fd_to_handle{$read_fd};
    my $nread = sysread ($handle, $buf, 80);
    #print "nread: $nread\n";
    $fd_to_expiry{$read_fd} = $now + $TIME_OUT;
    #my @chars = unpack ("A A A A A A A A A A A A A A A A A", $buf);
    #print "chars: " . Dumper \@chars;
    my $str = unpack ("A*", $buf);
    print "read $read_fd: $str\n";

    if ( $nread == 0   # disconnected socket
      || $str eq "quit")   # user quitting
    { 
      delete $fd_to_handle{$read_fd};
      delete $fd_to_expiry{$read_fd};
      vec($save_set, $read_fd, 1) = 0;
      print "Quit from socket $read_fd\n";
      close($handle);
      next;
    }
    if (length($str) == 0) {
      next; # nothing to do
    }

    my $write_cnt = 0;
    my $wbits = $save_set;

    #select RBITS,WBITS,EBITS,TIMEOUT
    select (undef, $wbits, undef, $TIME_OUT);

    while (my ($write_fd, $handle) = each %fd_to_handle) {
      if ( $write_fd == $listen_fd
        || $write_fd == $read_fd      # don't echo to originator
        || !vec ($wbits, $write_fd, 1))
      {
        next;
      }

      syswrite ($handle, "$str\n");
      print ("write $write_fd: $str\n");
      $write_cnt++;
    }
    if (!$write_cnt) {
      print "No other telnet sessions. Message not copied: $str\n";
    }

  }  # for loop for existing connections

  $save_set = start_end_alarm(\%fd_to_handle, \%fd_to_expiry, $save_set);

} # while(1)

sub start_end_alarm {
  my ($fd_to_handle, $fd_to_expiry, $save_set) = @_;
  my $now = time();
  my $min_expiry = 0;

  foreach my $fd (keys %$fd_to_expiry) {
    my $expiry = $fd_to_expiry->{$fd};
    if ($expiry == 0) {
      next;
    }

    if ($expiry <= $now) {
      print ("Time out socket $fd. Inactivity of $TIME_OUT sec. Closing socket.\n");

      my $handle = $fd_to_handle->{$fd};
      delete $fd_to_handle->{$fd};
      delete $fd_to_expiry->{$fd};
      vec($save_set, $fd, 1) = 0;
      close($handle);

      next;
    }

    $min_expiry = min ($min_expiry, $expiry)
  }

  # setting the alarm to the smallest expiration of the multiple sockets we are tracking
  if ($min_expiry) {
    my $future = $min_expiry - $now;
    $future = min  (1, $future);
    print "sig_handler alarm ($future)\n";
    alarm ($future);
  }

  return $save_set
}
