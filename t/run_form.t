use strict;
use warnings;

use File::Temp;
use Test::More tests => 11;

BEGIN { use_ok('Math::FORM') };

#try to find a FORM executable
my $form_cmd;
eval{
    require File::Which;
    File::Which->import();
};
if(! $@){
    $form_cmd = which('form');
    $form_cmd // ($form_cmd = which('tform'));
}
else{
    $form_cmd = `which form`;
    #$? tells us whether this was successful 
    #(= which exists and form was found)
    if($?){
	$form_cmd = `which tform`;
    }
    chomp $form_cmd;
}

SKIP: {
    skip 
	"No form installation found.",
	10
	if ! $form_cmd;


    print "Using $form_cmd to run form\n";

    #So we found something. Is it really FORM?
    #create minimal FORM program
    my $tmp_hdl = File::Temp->new(SUFFIX => '.frm');
    print $tmp_hdl "#-\noff finalstats;\n.end\n";
    close $tmp_hdl;
    system($form_cmd => $tmp_hdl->filename);
  SKIP: {
      skip "$form_cmd does not seem to be a valid FORM executable.",
	  10
	  if $?;

       #create FORM program for test
      $tmp_hdl = File::Temp->new(SUFFIX => '.frm');
      print $tmp_hdl <<__EOF__
	  #-
	  off finalstats;
	  #setexternal `PIPE1_'
	  #do SHELLLOOP=1,1
	  #redefine SHELLLOOP "0"
	  #fromexternal-
	  #enddo
__EOF__
	  ;
      
      #now finally we can test
      
      my $form_proc;
      ok(
	  $form_proc = Math::FORM->run(
	   $form_cmd => $tmp_hdl->filename
	 ), 
	 "launch FORM process"
	  )
	  or BAIL_OUT "Unable to launch form. Aborting";
      ok(
	  $form_proc->send('#toexternal "Hello world\n\n"'),
	 "send message to FORM"
	  )
	  or BAIL_OUT "Unable to send message to FORM. Aborting";
      
      is($form_proc->read,"Hello world\n","read message from FORM (1)");
      is($form_proc->read,"\n","read message from FORM (2)");
      ok(
	  $form_proc->kill(0),
	  "send signal to FORM"
	  );
      $form_proc->send('#prompt @');
      ok(
	  $form_proc->set_prompt('@'),
	 "change FORM prompt (1)"
	  );
      ok(
	  $form_proc->send('#toexternal "Hello; world;"'),
	 "change FORM prompt (2)"
	  );
      is(
	  $form_proc->read(';'),
	  "Hello;",
	  "read with changed delimiter (1)"
	  );
      ok(
	  $form_proc->set_delim(';'),
	  "change delimiter"
	  );
      is(
	  $form_proc->read(),
	  " world;",
	  "read with changed delimiter (2)"
	  );
      $form_proc->send('.end');
      $form_proc->wait,
    }
}
