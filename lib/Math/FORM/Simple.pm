package Math::FORM::Simple;

=head1 NAME

Math::FORM::Simple - Simple interface to the computer algebra system FORM

=cut

use warnings;
use strict;
use 5.10.1;

our $VERSION = '1.0';

use IO::Handle;
use Fcntl qw(F_SETFD);
use Carp;
use Time::HiRes qw(usleep);

=head1 SYNOPSIS

 use Math::FORM::Simple;

 my $FORM_proc = Math::FORM::Simple->run($FORM_cmd => $FORM_file);

 $FORM_proc->send("whatever your FORM program expects"); 
 my $from_FORM = $FORM_proc->read; 

 # wait for the FORM program to finish
 $FORM_proc->wait;

=head1 DESCRIPTION

Math::FORM::Simple aims to make communication with FORM programs as
simple as possible. It provides methods to start up FORM programs, send
commands, read the programs' answers, and - if push comes to shove -
kill them.

Note that, of course, the FORM program has to be written in such a way
that it expects communication with an external program. On the FORM
side, it is enough to use C<#setexternal `PIPE1_'> to establish the
connection. Afterwards messages can be sent and received using
C<#toexternal "message text"> and C<#fromexternal>, respectively. For
more information on the FORM side of things, read the chapter on
external communication in the FORM reference manual. All ugly things are
done for you by Math::FORM::Simple, so you can skip those parts.

=cut

=head1 METHODS

=over

=item B<run>

Start a new FORM process. The first argument is the command used to
launch form. The second argument is the name of the file containing the
FORM program.

=cut

sub run{
    my $class=shift;
    my $self={};
    bless($self,$class);
    $self->{delim}="\n";
    $self->{prompt}="";
    $self->_spawn(@_);
    return $self;
}

=item B<send>

Send some text to the FORM process. For each argument there should be a
corresponding C<#fromexternal> in the FORM program.

=cut

sub send{
    my $self=shift;
    my $to_FORM=$self->{to_FORM};
    my @messages=@_;
    my $prompt_removed=0;;
    if($Math::FORM::Simple::rm_prompt){
	map {
	    $prompt_removed = 1 if s/\n$self->{prompt}\n//sg;
	    $_
	} @messages ;
	map {s/\n$self->{prompt}$//} @messages ;
    }
    carp "removed prompt from message(s)" if $prompt_removed;
    map {$_.="\n$self->{prompt}\n"} @messages;
    print $to_FORM (@messages);
}

=item B<read>

Read some string sent by FORM via C<#toexternal>. If a delimiter is
given as an argument all text up to this delimiter is read. The default
is to read up to the first newline.

=cut

sub read{
    my $self=shift;
    my $delim=shift;
    my $from_FORM=$self->{from_FORM};
    $delim // ($delim=$self->{delim});
    local $/=$delim;
    return <$from_FORM>;
}

=item B<wait>

Wait for the FORM process to finish. It is usually a good idea to do
this before the end of your perl script (or, more precisely, before your
Math::FORM::Simple object is being destroyed). If you don't wait the
FORM process will be terminated forcefully at that point. 

=for comment

You can give a flag as an argument which will be passed to a L<waitpid>
system call.

=cut

sub wait{
    my $self=shift;
    #TODO $flag is not being used
    #my $flag=shift;
    #$flag // ($flag=0);
    usleep 0.1 while(kill 0 => $self->{FORM_pid});
}

=item B<kill>

Send a signal to the FORM process. The first argument should be the
signal to be sent. Useful signals are e.g. 15 to kill the FORM process,
9 to kill it B<now>, and 0 to check whether it is still alive. Note that
it is usually not necessary to kill the FORM process manually. See the
description of kill in "perldoc perlfunc" for more details.

=cut

sub kill{
    my $self=shift;
    my $signal=shift;
    kill $signal,$self->{FORM_pid} if $self->{FORM_pid};
}

=item B<set_delim>

Set the default delimiter for B<read>.

=cut

sub set_delim{
    my $self=shift;
    $self->{delim}=shift;
}

=item B<set_prompt>

Change the prompt. This is relevant if (and only if) you have changed
the prompt in your FORM program with the C<#prompt> statement. Of
course, the Math::FORM::Simple prompt must always match the one defined
in your FORM program for things to work properly.

=cut


sub set_prompt{
    my $self=shift;
    $self->{prompt}=shift;
}

=item B<print>

Print a string to the pipe to the FORM process. This is a rather
low-level method, so in most cases the B<send> method should be used
instead . In particular the FORM prompt is not being set and there is no
guarantee that FORM will actually ever read what is printed. If the string
being printed however contains the FORM prompt somewhere in the middle,
FORM will read up to that point and then stop. Depending on your system
B<print> will probably block or simply fail at some point when the pipe
is full and no prompt has been sent.

=cut

sub print{
    my $self=shift;
    my $to_FORM=$self->{to_FORM};
    print $to_FORM (@_);
}

=back

=cut


sub _spawn{
    my $self=shift;
    my $form_cmd=shift;
    my $form_file=shift;
    $form_cmd or croak "Failed to spawn FORM process: missing FORM command";
    my $pid;
    my ($FORM_rdr,$FORM_wtr);

    #prepare pipes
    pipe($self->{from_FORM},$FORM_wtr) or die "Failed to open pipe: $!";
    pipe($FORM_rdr,$self->{to_FORM}) or die "Failed to open pipe: $!";
    $self->{to_FORM}->autoflush(1);

    #spawn new form process
    if($pid=fork()){
	#parent
	my $from_FORM=$self->{from_FORM};
	my $to_FORM=$self->{to_FORM};
	local $/="\n";
	close $FORM_rdr;
	close $FORM_wtr;
	$self->{FORM_pid}=<$from_FORM>;
	$self->{FORM_pid} 
	// die "Failed to establish channel to FORM: received no pid";
	chomp $self->{FORM_pid};
	say $to_FORM "$self->{FORM_pid},$$";
    }
    else{
	#child (FORM process)
	$pid // die "Failed to fork: $!";
	close $self->{to_FORM};
	close $self->{from_FORM};

	#clear close-on-exec flags
	fcntl($FORM_rdr,F_SETFD,0)
	    or die "Failed to clear close-on-exec: $!";;
	fcntl($FORM_wtr,F_SETFD,0)
	    or die "Failed to clear close-on-exec: $!";;

	#get file descriptors from handles
	my $rdr_fd=fileno $FORM_rdr;
	my $wtr_fd=fileno $FORM_wtr;

	my $cmd="$form_cmd -pipe $rdr_fd,$wtr_fd ";
	$cmd.=$form_file if $form_file;
	exec "$cmd"
	    or croak "Failed to exec '$cmd': $!";
    }
}

sub DESTROY{
    my $self=shift;
    my $to_FORM=$self->{to_FORM};
    my $from_FORM=$self->{from_FORM};
    close  $self->{to_FORM} if $self->{to_FORM} ;
    close  $self->{from_FORM} if $self->{from_FORM};
    if($self->{FORM_pid}){
	#give FORM some time to die
	$self->kill(15);
	my $life_time = time()+$Math::FORM::Simple::timeout;
	while($life_time > time()){
	    return if(! $self->kill(0));
	    usleep 0.1;
	}
	#kill it
	$self->kill(9);
    }
}


=head1 FLAGS

=over

=item C<$Math::FORM::Simple::timeout>

When the object is destroyed, it first tries to terminate the associated FORM 
process gracefully. This flag sets the time in seconds after which brute 
force will be used.

=item C<$Math::FORM::Simple::rm_prompt>

If set to zero, the B<send> method will no longer remove the FORM prompt from 
messages.

=item C<$Math::FORM::Simple::warn>

Disables non-fatal warnings when set to zero.

=back

=cut

BEGIN {
    $Math::FORM::Simple::timeout = 3;
    $Math::FORM::Simple::rm_prompt = 1;
    $Math::FORM::Simple::warn = 1;
}

=head1 SEE ALSO

L<The FORM reference manual|http://www.nikhef.nl/~form/maindir/documentation/reference/online/online.html>

=head1 AUTHOR

Andreas Maier, E<lt>maier@to.infn.itE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Andreas Maier

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut


42;
