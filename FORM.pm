package FORM;
#establishes communication to a newly spawned FORM process

use warnings;
use strict;
use 5.10.1;
use IO::Handle;
use POSIX qw(WNOHANG);
use Fcntl qw(F_SETFD);
use Carp;

BEGIN {
    $FORM::timeout = 3;
    $FORM::rm_prompt = 1;
}

sub new{
    my $class=shift;
    my $self={};
    bless($self,$class);
    $self->{delim}="\n";
    $self->{prompt}="";
    $self->_spawn(@_);
    return $self;
}

sub print{
    my $self=shift;
    my $to_FORM=$self->{to_FORM};
    print $to_FORM (@_);
}

sub send{
    my $self=shift;
    my $to_FORM=$self->{to_FORM};
    my @messages=@_;
    if($FORM::rm_prompt){
	map {s/\n$self->{prompt}\n//sg} @messages ;
	map {s/\n$self->{prompt}$//} @messages ;
    }
    map {$_.="\n$self->{prompt}\n"} @messages;
    print $to_FORM (@messages);
}

sub set_delim{
    my $self=shift;
    $self->{delim}=shift;
}

sub set_prompt{
    my $self=shift;
    $self->{prompt}=shift;
}

sub read{
    my $self=shift;
    my $delim=shift;
    my $from_FORM=$self->{from_FORM};
    $delim // ($delim=$self->{delim});
    local $/=$delim;
    return <$from_FORM>;
}

sub kill{
    my $self=shift;
    my $signal=shift;
    kill $signal,$self->{FORM_pid} if $self->{FORM_pid};
}

sub wait{
    my $self=shift;
    my $flag=shift;
    $flag // ($flag=0);
    waitpid($self->{FORM_pid},$flag);
}

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
	say "starting $cmd";
	exec "$cmd"
	    or die "Failed to exec '$cmd': $!";
    }
}

sub DESTROY{
    my $self=shift;
    my $status=$?;
    my $to_FORM=$self->{to_FORM};
    my $from_FORM=$self->{from_FORM};
    close  $self->{to_FORM} if $self->{to_FORM} ;
    close  $self->{from_FORM} if $self->{from_FORM};
    if($self->{FORM_pid}){
	#give FORM some time to die
	$self->kill(15);
	my $life_time = time()+$FORM::timeout;
	while($life_time > time()){
	    if(waitpid($self->{FORM_pid},WNOHANG)) {
		$?=$status;
		return;
	    };
	    sleep 1;
	}
	#kill it
	$self->kill(9);
    }
    $?=$status; #restore status
}


42;
