##############################################
# $Id: 20_FRM_PULSECNT.pm 7111 2014-12-01 14:13:26Z ntruchsess $
##############################################
package main;

use strict;
use warnings;
use Data::Dumper;

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use Device::Firmata::Constants  qw/ :all /;

#####################################

my %sets = (
  "reset" => "noArg",
  "offset"=> "",
);

my %gets = (
  "position" => "noArg",
  "offset"   => "noArg",
  "value"    => "noArg",
);

sub
FRM_PULSECNT_Initialize($)
{
  my ($hash) = @_;



  $hash->{SetFn}     = "FRM_PULSECNT_Set";
  $hash->{GetFn}     = "FRM_PULSECNT_Get";
  $hash->{AttrFn}    = "FRM_PULSECNT_Attr";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_PULSECNT_Init";
  $hash->{UndefFn}   = "FRM_PULSECNT_Undef";
  $hash->{StateFn}   = "FRM_PULSECNT_State";

  $hash->{AttrList}  = "IODev $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_PULSECNT_Init($$)
{
	my ($hash,$args) = @_;

	my $u = "wrong syntax: define <name> FRM_PULSECNT pin id minPauseBefore_us minPulseLength_us maxPulseLength_us";
  	return $u unless defined $args and int(@$args) == 5;
 	my $pin = @$args[0];
 	my $pulseCntNum = @$args[1];
	my $minPauseBefore_us = @$args[2];
	my $minPulseLength_us = @$args[3];
	my $maxPulseLength_us =@$args[4];
 	my $name = $hash->{NAME};

#	print STDERR "FRM_PULSECNT_Init";
#	print STDERR Dumper($hash);
	Log3 $hash->{NAME}, 1, "[$name] pin=$pin id=$pulseCntNum minPauseBefore_us=$minPauseBefore_us minPulseLength_us=$minPulseLength_us maxPulseLength_us=$maxPulseLength_us";


	$hash->{PIN} = $pin;
	$hash->{CNTNUM} = $pulseCntNum;
	$hash->{minPauseBefore_us} = $minPauseBefore_us;
	$hash->{minPulseLength_us} = $minPulseLength_us;
	$hash->{maxPulseLength_us} = $maxPulseLength_us;

	eval {
		FRM_Client_AssignIOPort($hash);
		my $firmata = FRM_Client_FirmataDevice($hash);
		$firmata->pulsecounter_attach($pulseCntNum, $pin, $minPauseBefore_us, $minPulseLength_us, $maxPulseLength_us);
		$firmata->oberve_pulsecnt($pulseCntNum, \&FRM_PULSECNT_observer, $hash);
#		$firmata->observe_pulsecounter(\&FRM_PULSECNT_observer, $hash );
		Log3 $name, 1, "after";
	};
	if ($@) {
		$@ =~ /^(.*)( at.*FHEM.*)$/;
		$hash->{STATE} = "error initializing: ".$1;
		return "error initializing '$name': $1";
	}

	if (! (defined AttrVal($name,"stateFormat",undef))) {
		$main::attr{$name}{"stateFormat"} = "counter";
	}

  $hash->{offset} = ReadingsVal($name,"counter",0);

	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_PULSECNT_observer
{
	my ($id, $cnt_shortPause, $cnt_shortPulse, $cnt_longPulse, $cnt_pulse, $hash) = @_;
	my $name = $hash->{NAME};
	main::readingsBeginUpdate($hash);
	main::readingsBulkUpdate($hash,"cnt_shortPause",$cnt_shortPause, 1);
	main::readingsBulkUpdate($hash,"cnt_shortPulse",$cnt_shortPulse, 1);
	main::readingsBulkUpdate($hash,"cnt_longPulse",$cnt_longPulse, 1);
	main::readingsBulkUpdate($hash,"cnt_pulse",$cnt_pulse, 1);
	main::readingsEndUpdate($hash,1);
	print STDERR "FRM_PULSECNT_observer $cnt_pulse";
}

sub
FRM_PULSECNT_Set
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  my $command = $a[1];
  my $value = $a[2];
  if(!defined($sets{$command})) {
  	my @commands = ();
    foreach my $key (sort keys %sets) {
      push @commands, $sets{$key} ? $key.":".join(",",$sets{$key}) : $key;
    }
    return "Unknown argument $a[1], choose one of " . join(" ", @commands);
  }
  COMMAND_HANDLER: {
    $command eq "reset" and do {
      eval {
        FRM_Client_FirmataDevice($hash)->encoder_reset_position($hash->{ENCODERNUM});
      };
      main::readingsBeginUpdate($hash);
      main::readingsBulkUpdate($hash,"position",$hash->{offset},1);
      main::readingsBulkUpdate($hash,"value",0,1);
      main::readingsEndUpdate($hash,1);
      last;
    };
    $command eq "offset" and do {
      $hash->{offset} = $value;
      readingsSingleUpdate($hash,"position",ReadingsVal($hash->{NAME},"value",0)+$value,1);
      last;
    };
  }
}

sub
FRM_PULSECNT_Get($)
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  my $command = $a[1];
  my $value = $a[2];
  if(!defined($gets{$command})) {
  	my @commands = ();
    foreach my $key (sort keys %gets) {
      push @commands, $gets{$key} ? $key.":".join(",",$gets{$key}) : $key;
    }
    return "Unknown argument $a[1], choose one of " . join(" ", @commands);
  }
  my $name = shift @a;
  my $cmd = shift @a;
  ARGUMENT_HANDLER: {
    $cmd eq "position" and do {
      return ReadingsVal($hash->{NAME},"position","0");
    };
    $cmd eq "offset" and do {
      return $hash->{offset};
    };
    $cmd eq "value" and do {
      return ReadingsVal($hash->{NAME},"value","0");
    };
  }
  return undef;
}

sub
FRM_PULSECNT_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $main::defs{$name};
  eval {
    if ($command eq "set") {
      ARGUMENT_HANDLER: {
        $attribute eq "IODev" and do {
          if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $value)) {
            FRM_Client_AssignIOPort($hash,$value);
            FRM_Init_Client($hash) if (defined ($hash->{IODev}));
          }
          last;
        };
      }
    }
  };
  if ($@) {
    $@ =~ /^(.*)( at.*FHEM.*)$/;
    $hash->{STATE} = "error setting $attribute to $value: ".$1;
    return "cannot $command attribute $attribute to $value for $name: ".$1;
  }
}

sub
FRM_PULSECNT_Undef($$)
{
  my ($hash, $name) = @_;
  my $pinA = $hash->{PINA};
  my $pinB = $hash->{PINB};
  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    $firmata->encoder_detach($hash->{ENCODERNUM});
    $firmata->pin_mode($pinA,PIN_ANALOG);
    $firmata->pin_mode($pinB,PIN_ANALOG);
  };
  if ($@) {
    eval {
      my $firmata = FRM_Client_FirmataDevice($hash);
      $firmata->pin_mode($pinA,PIN_INPUT);
      $firmata->digital_write($pinA,0);
      $firmata->pin_mode($pinB,PIN_INPUT);
      $firmata->digital_write($pinB,0);
    };
  }
  return undef;
}

sub
FRM_PULSECNT_State($$$$)
{
  my ($hash, $tim, $sname, $sval) = @_;
  if ($sname eq "position") {
    $hash->{offset} = $sval;
  }
  return undef;
}

1;

=pod
=begin html

<a name="FRM_PULSECNT"></a>
<h3>FRM_PULSECNT</h3>
<ul>
	represents a pulse counter to count digital pulses e.g. S0-Zähler running <a href="http://www.firmata.org">Firmata</a><br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br>

  <a name="FRM_PULSECNTdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_PULSECNT &lt;pin&gt; &lt;id&gt; &lt;minPauseBefore_us&gt; &lt;minPulseLength_us&gt; &lt;maxPulseLength_us&gt;</code> <br>
  Defines the FRM_PULSECNT device. &lt;pin&gt; is the device pin to use.<br>
  [id] is the instance-id of the counter. Must be a unique number per FRM-device (rages from 0-1 depending on Firmata being used.<br>

	The three time values &lt;minPauseBefore_us&gt; &lt;minPulseLength_us&gt; &lt;maxPulseLength_us&gt; define a valid pulse.
	Valid pulses are counted in reading &lt;cnt_pulse&gt;. Too long pulses are stored in &lt;cnt_longPulse&gt;. Too short pulses are stored
	in &lt;cnt_shortPulse&gt;. If the pause between pulses is too short the pulse is not counted. The reading &lt;cnt_shortPause&gt; counts
	this events.
  </ul>

  <br>
  <a name="FRM_PULSECNTset"></a>
  <b>Set</b><br>
  <a name="FRM_PULSECNTget"></a>
  <b>Get</b>
  <ul>
  </ul><br>
  <a name="FRM_PULSECNTattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#FRM">FRM</a> to use. (Optional, only required if there is more
      than one FRM-device defined.)
      </li>
    </ul>
  </ul>
<br>

=end html
=cut
