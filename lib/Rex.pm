#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:

=head1 NAME

Rex - Remote Execution

=head1 DESCRIPTION

(R)?ex is a small script to ease the execution of remote commands. You can write small tasks in a file named I<Rexfile>.

You can find examples and howtos on L<http://rexify.org/>

=head1 GETTING HELP

=over 4

=item * Web Site: L<http://rexify.org/>

=item * IRC: irc.freenode.net #rex

=item * Bug Tracker: L<https://rt.cpan.org/Dist/Display.html?Queue=Rex>

=item * Twitter: L<http://twitter.com/jfried83>

=back

=head1 Dependencies

=over 4

=item *

L<Net::SSH2>

=item *

L<Expect>

Only if you want to use the Rsync module.

=item *

L<DBI>

Only if you want to use the DB module.

=back

=head1 SYNOPSIS

 desc "Show Unix version";
 task "uname", sub {
     say run "uname -a";
 };

 bash# rex -H "server[01..10]" uname

See L<Rex::Commands> for a list of all commands you can use.

=head1 CLASS METHODS

=over 4

=cut


package Rex;

use strict;
use warnings;

use Net::SSH2;
use Rex::Logger;
use Rex::Cache;

require Exporter;
use base qw(Exporter);

use vars qw(@EXPORT $VERSION @CONNECTION_STACK);

@EXPORT = qw($VERSION);
$VERSION = "0.24.1";

sub push_connection {
   push @CONNECTION_STACK, $_[0];
}

sub pop_connection {
   pop @CONNECTION_STACK;
   Rex::Logger::debug("Connections in queue: " . scalar(@CONNECTION_STACK));
}

=item get_current_connection

Returns the current connection as a hashRef.

=over 4

=item server

The server name

=item ssh

1 if it is a ssh connection, 0 if not.

=back

=cut

sub get_current_connection {
   $CONNECTION_STACK[-1];
}

=item is_ssh

Returns 1 if the current connection is a ssh connection. 0 if not.

=cut

sub is_ssh {
   if($CONNECTION_STACK[-1]) {
      return $CONNECTION_STACK[-1]->{"ssh"};
   }

   return 0;
}

=item get_sftp

Returns the sftp object for the current ssh connection.

=cut

sub get_sftp {
   if($CONNECTION_STACK[-1]) {
      return $CONNECTION_STACK[-1]->{"sftp"};
   }

   return 0;
}

sub get_cache {
   if($CONNECTION_STACK[-1]) {
      return $CONNECTION_STACK[-1]->{"cache"};
   }

   return Rex::Cache->new;
}

sub connect {

   my ($param) = { @_ };

   my $server  = $param->{server};
   my $port    = $param->{port} || 22;
   my $timeout = $param->{timeout} || 5;
   my $user = $param->{"user"};
   my $pass = $param->{"password"};


   my $ssh = Net::SSH2->new;

   my $fail_connect = 0;
   CON_SSH:
      if($server =~ m/^(.*?):(\d+)$/) {
         $server = $1;
         $port   = $2;
      }

      Rex::Logger::info("Connecting to $server:$port (" . $user . ")");
      unless($ssh->connect($server, $port, Timeout => $timeout)) {
         ++$fail_connect;
         sleep 1;
         goto CON_SSH if($fail_connect < 3); # try connecting 3 times

         Rex::Logger::info("Can't connect to $server");

         die("Can't connect to $server"); # kind beenden
      }

   my $auth_ret;
   if(! exists $param->{private_key}) {
      $auth_ret = $ssh->auth_password($user, $pass);
   }
   elsif(exists $param->{private_key} && exists $param->{public_key}) {
      $auth_ret = $ssh->auth_publickey($user, 
                              $param->{public_key}, 
                              $param->{private_key}, 
                              $pass);
      print  "h: $auth_ret\n";
   }
   else {
      $auth_ret = $ssh->auth('username' => $user,
                             'password' => $pass,
                             'publickey' => $param->{public_key} || "",
                             'privatekey' => $param->{private_key} || "");
   }

   # push a remote connection
   Rex::push_connection({ssh => $ssh, server => $server, sftp => $ssh->sftp?$ssh->sftp:undef, cache => Rex::Cache->new});

   Rex::Logger::debug("Current Error-Code: " . $ssh->error());

   # auth unsuccessfull
   unless($auth_ret) {
      Rex::Logger::info("Wrong username or password. Or wrong key.");
      # after jobs

      die("Wrong username or password. Or wrong key.");
   }
}


=back

=cut

1;
