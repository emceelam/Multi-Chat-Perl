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


Readonly my $PORT => 4023;
Readonly my $TIME_OUT => 10;


print <<TEXT
Multi client chat server, using telnet, programmed in C
To connect:
    telnet 127.0.0.1 $PORT

Everything typed by one chat user will be copied to other chat users.
Typing 'quit' on telnet sessions will disconnect.
TEXT
;

my $sigset    = POSIX::SigSet->new(SIGPIPE);
my $sigaction = POSIX::SigAction->new(sub { exit(0) } , $sigset, SA_NOCLDSTOP);


=begin comment

  // set up listenfd socket
  int listenfd;
  listenfd = socket(AF_INET, SOCK_STREAM, 0);
  if (listenfd < 0) {
    perror ("socket() failed");
    exit(1);
  }

=end comment
=cut

my $listen_handle;
socket($listen_handle, AF_INET, SOCK_STREAM, 0);

=begin comment
  // only has meaning if children are still using same port as parent,
  // and you restart the parent
  int on = 1;
  if (setsockopt (listenfd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on)) < 0) {
    perror("setsockopt() fails");
    exit(1);
  }
=end comment
=cut

setsockopt($listen_handle, SOL_SOCKET, SO_REUSEADDR, pack("l", 1));

=begin comment
  # bind
  struct sockaddr_in sin;
  sin.sin_family = AF_INET;
  sin.sin_port = htons(PORT);
  sin.sin_addr.s_addr = htonl(INADDR_ANY);
  if (bind(listenfd, (struct sockaddr *) &sin, sizeof(sin)) < 0) {
    perror ("Binding error in server!");
    exit(1);
  }
=end comment
=cut

my $sockaddr = pack_sockaddr_in ($PORT, INADDR_ANY);
bind ($listen_handle, $sockaddr);

=begin comment
  // listen
  int backlog = 5;   // max length of queue of pending connections.
  if (listen(listenfd, backlog) < 0) {
    perror ("Listen error in server!");
    exit(1);
  }
  printf ("Listening on socket %d for client connections\n", listenfd);

=end comment
=cut

my $backlog = 5;
listen ($listen_handle, $backlog);

=begin comment
  // main loop
  // block for incoming socket communications
  fd_set readset;
  char chat[CHAT_SIZE];
  int connfd;
  int return_val;
  FD_ZERO(&saveset);
  FD_SET(listenfd, &saveset);
  memset (sock_expiry, 0, sizeof(sock_expiry));
  while(1) {
    memcpy (&readset, &saveset, sizeof(fd_set));
    return_val =
      pselect (
        MAX_FD,      // nfds, number of file descriptors
        &readset,    // readfds
        NULL,        // writefds
        NULL,        // exceptfds, almost never used
        NULL,        // struct timeval *timeout, NULL for always block
        &empty_set   // sigmask, allow signal processing during select
      );
    if (return_val == -1 && errno == EINTR) {
      // signal handling has interrupted pselect()
      continue;
    }
=end comment
=cut

my %fd_to_handle;
my $listen_fd = fileno($listen_handle);
$fd_to_handle{$listen_fd} = $listen_handle;


my $save_set = "";
my $rbits;
vec($save_set, $listen_fd, 1) = 1;
my $loop_cnt = 0;
my %fd_to_expiry;
while (1) {
  # print "rin: " . unpack ("H*", $save_set) . "\n";
  $rbits = $save_set;

  # select RBITS,WBITS,EBITS,TIMEOUT
  select ($rbits, undef, undef, $TIME_OUT);

=begin comment

    // incoming connection
    int now = time(NULL);
    if (FD_ISSET(listenfd, &readset)) {
      connfd = accept(listenfd, NULL, NULL);
        // will not block because accept has data
      printf ("Connection from socket %d\n", connfd);
      FD_SET(connfd, &saveset);
      sock_expiry[connfd] = now + TIME_OUT;
=end comment
=cut

  #print "loop_cnt: " . $loop_cnt++ . "\n";
  #print "rbits hex:  " . unpack ("H*", $rbits) . "\n";
  #print "rbits bits: " . unpack ("B*", $rbits) . "\n";
  my $max_fd = length unpack ("B*", $rbits);
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


=begin comment
      /*
       * set no linger
       * onoff=1 and ling=0:
       *   The connection is aborted on close,
       *   and all data queued for sending is discarded.
       *                   
       *  struct linger {
       *       int l_linger;   // how many seconds to linger for
       *       int l_onoff;    // linger active
       *   };
       */
      struct linger stay;
      stay.l_onoff  = 1;
      stay.l_linger = 0;
      setsockopt(connfd, SOL_SOCKET, SO_LINGER, &stay, sizeof(struct linger));
=end comment
=cut

    my $packed = pack("l l", 0, 1);
    #print "SO_LINGER packed: " . unpack ("H*", $packed) . "\n";
    setsockopt($conn_handle, SOL_SOCKET, SO_LINGER, $packed);

=begin comment
      // set connfd to be non-blocking socket
      int val;
      val = fcntl(connfd, F_GETFL, 0);
      if (val < 0) {
        perror ("fcntl(F_GETFL) failed");
      }
      val = fcntl(connfd, F_SETFL, val | O_NONBLOCK);
      if (val < 0) {
        perror ("fcntl(F_SETFL) failed");
      }
    }
=end comment
=cut

    my $flags = fcntl($conn_handle, F_GETFL, 0);
    fcntl($conn_handle, F_SETFL, $flags | O_NONBLOCK);
  }

=begin comment
    // existing connections
    int readsock;
    for (readsock = listenfd +1; readsock < MAX_FD ; readsock++) {
      if (!FD_ISSET(readsock, &readset)) {
        continue;
      }
      
=end comment
=cut
  foreach my $read_fd ( ($listen_fd+1)..$max_fd) {
    if (!vec ($rbits, $read_fd, 1)) {
      next;
    }
    print "socket fd $read_fd is readable\n";
  

=begin comment

      memset (chat, 0, CHAT_SIZE);
      int nread = read (readsock, chat, CHAT_SIZE);
      if (nread < 0) {
        fprintf (stderr,
          "read() failed on sock %d: %s\n", readsock, strerror(errno));
        exit(1);
      }
      chat[strcspn(chat, "\r\n")] = '\0';  // chomp
      sock_expiry[readsock] = now + TIME_OUT;

=end comment
=cut
    my $buf = pack ("C80",0);
    my $handle = $fd_to_handle{$read_fd};
    my $nread = sysread ($handle, $buf, 80);
    #print "nread: $nread\n";
    $fd_to_expiry{$read_fd} = $now + $TIME_OUT;
    #my @chars = unpack ("A A A A A A A A A A A A A A A A A", $buf);
    #print "chars: " . Dumper \@chars;
    my $str = unpack ("A*", $buf);
    print "read $read_fd: $str\n";

=begin comment
      if ( nread == 0  // disconnected socket
        || strcmp(chat, "quit") == 0) // user quitting
      {
        FD_CLR (readsock, &saveset);
        close(readsock);
        sock_expiry[readsock] = 0;
        printf ("Quit from socket %d\n", readsock);
        continue;
      }
      if (strlen(chat) == 0) {
        continue;  // nothing to do
      }
      printf ("Read socket %d: '%s'\n", readsock, chat);
=end comment
=cut
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

=begin comment
      // write chat to all other clients
      int writesock;
      int writecnt = 0;
      struct timeval tv;
      fd_set writeset;
      memcpy (&writeset, &saveset, sizeof(fd_set));
      tv.tv_sec  = 0;
      tv.tv_usec = 0;
      select (MAX_FD, NULL, &writeset, NULL, &tv);
        // which sockets can we write to
      for (writesock = listenfd +1; writesock < MAX_FD; writesock++) {
        if (  writesock == readsock   // don't echo to originator 
          || !FD_ISSET(writesock, &writeset))
        {
          continue;
        }

        printf ("Write socket %d: %s\n", writesock, chat);
        writecnt++;
        if (write (writesock, chat, CHAT_SIZE) < 0) {
          fprintf (stderr,
            "write() failed on sock %d: %s\n", writesock, strerror(errno));
          exit(1);
        }
      }
      if (!writecnt) {
        printf ("No other telnet sessions. Message not copied: '%s'\n", chat);
      }

    }//for loop for existing connections

    start_end_alarm(sock_expiry, &saveset);

  }//while(1)


=end comment
=cut

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

  $save_set = start_end_alarm(\%fd_to_handle, \%fd_to_expiry, $save_set, $max_fd);

} # while(1)

sub start_end_alarm {
  my ($fd_to_handle, $fd_to_expiry, $save_set, $max_fd) = @_;
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
