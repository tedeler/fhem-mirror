#################################################################################
#
# $Id: 89_VCONTROL300.pm 11340 2017-01-09 23:16:00Z srxp $
# FHEM Module for Viessman Vitotronic200
#
# Derived from 89_VCONTROL300.pm: Copyright (C) Stephan Ramel
#
# Die seriellen Schnittstellen sind unetr Windows aktuell nicht geifbar
# Bitte jemand mit Kenntnissen nasetzen ->> Danke!!!
#
# 2018-01-10 22:00 -V09.00 Heizkreiswarmwasserschema Erkennung "hscheme" hinzugefügt (300P)
#                      .01 TYPE_200_HOE3 hinzugefügt (300P)
#                      .03 einigen "toten" Code entfernt
# 2018-01-21 17:20 -V08 Pumpenventilbauart Erkennung "Valve" hinzugefügt (300P)
# 2018-01-06 17:10 -V07 Modul angepasst, sub DeleteInternal($$); SetInternal($$$); readingsUpdateByName($$$); und setDayHash($$);
#                       umbenannt in VCONTROL300_addSetParameterToList($$$$); VCONTROL300_DeleteInternal($$); VCONTROL300_SetInternal($$$);
#                       VCONTROL300_readingsUpdateByName($$$) und VCONTROL300_setDayHash($$);
# 2018-01-18 22:00 -V06 1. Änderung USB Device vs. TCP Connection Erkennung (Post #msg743442)
#                       2. erkenne Konfigurationsfehler in der ***.cfg Datei. Anzahl Spalten muss immer 6 sein! (Post #msg749864)  (by Patrik.S)
# 2018-01-01 11:30 -V05 Modul angepasst damit es auch mit configDB funktioniert (by crispyduck)
# 2017-11-21 23:00 -V04 Betriebsart Mapping ausgelagert in die Configdatei (by Patrik.S)
# 2017-11-15 22:05 -V03 Fehlercode Mapping ausgelagert in die Configdatei (by Patrik.S)
# 2017-11-15 15:45 -V02 Fehlercodes mit dessen Zeitstempel ausgeben (by Patrik.S)
# 2017-11-14 23:36 -V01 Initiale Version mit zusätzlicher Abfrage und Mapping der Fehlercodes (by Patrik.S)
#
# FHEM Module for Viessman Vitotronic200
#
# Derived from 89_VCONTROL300.pm: Copyright (C) Stephan Ramel
#
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
#
###########################
#package main;

use strict;
use warnings;
use Blocking;
use Time::HiRes qw(gettimeofday);
use Time::Local;
#use Tie::IxHash;

# Helper Constants
#use constant NO_SEND => 9999;
use constant POLL_ENABLED => 1;
use constant POLL_DISABLED => 0;
#use constant READ_ANSWER => 1;
#use constant READ_UNDEF => 0;
use constant GET_TIMER_ACTIVE => 1;
use constant GET_TIMER_PAUSED => 0;
use constant GET_CONFIG_ACTIVE => 1;
use constant GET_CONFIG_PAUSED => 0;
use constant SET_VALUES_ACTIVE => 1;
use constant SET_VALUES_PAUSED => 0;
use constant PROTOCOL_KW  => "kw";
use constant PROTOCOL_300 => "300";
use constant TYPE_200_WO1X => "200_WO1x";	# WO1x == Wärmepumengeräte
use constant TYPE_200_KWX => "200_KWx";		# Witterungsgeführte Kessel- u. Heizkreisregelung
use constant TYPE_200_HOXX => "200_HOxx";	# Brennwertkessel
use constant TYPE_200_HOE3 => "200_HOE3";	# Vitovalor 300P mit Brennwertkessel



#Poll Parameter
my $defaultPollInterval = 180;
my $defaultProtocol = PROTOCOL_300;
my $defaultFastPollSize = 0;
my $command_config_file = "";

my $poll_now = POLL_DISABLED;

my $get_timer_now = GET_TIMER_PAUSED;
my $get_config_now = GET_CONFIG_PAUSED;
my $set_values_now = SET_VALUES_PAUSED;



#actually used command list
my %current_cmd_hash;
my %poll_cmd_hash;
my %timer_cmd_hash;
my %set_cmd_hash;
my %set_cmd_hash_values;
my %mapping_errorstate_hash;		# mapping for error codes aka Stoerungscodes are defined in configuration file
my %mapping_operationstate_hash;	# optional mapping for operation modes are defined in configuration file. If not given the internal mappings are used according to attribute vitotronicType


#remember days for daystart values
my %DayHash;

#States the Heater can be SET to
my @mode;	# entries will be assigned by vitotronicType
my @mode_200_KWx = ("Nur_Warmwasser","Reduziert","Normal","Heizen_und_Warmwasser","Heizen_und_Warmwasser_FrostSchutz","Abschaltbetrieb");
my @mode_200_WO1x = ("Aus","Nur_Warmwasser","Heizen_und_Warmwasser","NA","Reduziert","Normal","Abschaltbetrieb","Nur_Kuehlen");
my @mode_200_HOxx = ("Abschaltbetrieb","Nur_Warmwasser","Heizen_und_Warmwasser","NA","NA","NA","NA","NA");
my @mode_200_HOE3 = ("Abschaltbetrieb","Nur_Warmwasser","Heizen_und_Warmwasser","Dauernd_Reduziert","Immer_Normal","NA","NA","NA");
my @state = ("off","on");

#States the Heater was read during POLLING
###     different device types according to: https://github.com/openv/openv/wiki/Ger%C3%A4te     ###
my %modus;	# entries will be assigned by vitotronicType

my %modus_200_KWx;		# Witterungsgeführte Kessel- u. Heizkreisregelung
$modus_200_KWx{'00'} = 'Nur_Warmwasser';
$modus_200_KWx{'01'} = 'Reduziert';
$modus_200_KWx{'02'} = 'Normal';
$modus_200_KWx{'03'} = 'Heizen_und_Warmwasser';
$modus_200_KWx{'04'} = 'Heizen_und_Warmwasser_FrostSchutz';
$modus_200_KWx{'05'} = 'Abschaltbetrieb';

my %modus_200_WO1x;		# WO1x == Wärmepumengeräte
$modus_200_WO1x{'00'} = 'Aus';
$modus_200_WO1x{'01'} = 'Nur_Warmwasser';
$modus_200_WO1x{'02'} = 'Heizen_und_Warmwasser';
#$modus_200_WO1x{'03'} = 'N/A';
$modus_200_WO1x{'04'} = 'Reduziert';
$modus_200_WO1x{'05'} = 'Normal';
$modus_200_WO1x{'06'} = 'Abschaltbetrieb';
$modus_200_WO1x{'07'} = 'Nur_Kuehlen';

my %modus_200_HOxx;		# Brennwertkessel
$modus_200_HOxx{'00'} = 'Abschaltbetrieb';
$modus_200_HOxx{'01'} = 'Nur_Warmwasser';
$modus_200_HOxx{'02'} = 'Heizen_und_Warmwasser';
#$modus_200_HOxx{'03'} = 'N/A';
#$modus_200_HOxx{'04'} = 'N/A';
#$modus_200_HOxx{'05'} = 'N/A';
#$modus_200_HOxx{'06'} = 'N/A';
#$modus_200_HOxx{'07'} = 'N/A';

my %modus_200_HOE3;		# Vitovalor mit Brennwertkessel
$modus_200_HOE3{'00'} = 'Abschaltbetrieb';
$modus_200_HOE3{'01'} = 'Nur_Warmwasser';
$modus_200_HOE3{'02'} = 'Heizen_und_Warmwasser';
$modus_200_HOE3{'03'} = 'Dauernd_Reduziert';
$modus_200_HOE3{'04'} = 'Immer_Normal';
$modus_200_HOE3{'05'} = '05 nicht bekannt';
$modus_200_HOE3{'06'} = '06 nicht bekannt';
$modus_200_HOE3{'07'} = '07 nicht bekannt';


my %status;
$status{'0'} = 'Aus';
$status{'1'} = 'An';

my %valve;    # V7 welche Art von Pumenventil
$valve{'0'} = 'kein Ventil - no valve';
$valve{'1'} = 'Viessmann_Ventil';
$valve{'2'} = 'Wilo_Ventil';
$valve{'3'} = 'Grundfos_Ventil';

my %hscheme;   #heating circuit hot water scheme (Heizkreiswarmwasserschema)
$hscheme{'1'} = 'A1';
$hscheme{'2'} = 'A1+WW';
$hscheme{'3'} = 'M2';
$hscheme{'4'} = 'M2+WW';
$hscheme{'5'} = 'A1+M1';
$hscheme{'6'} = 'A1+M2+WW';
$hscheme{'7'} = 'M2+M3';
$hscheme{'8'} = 'M2+M3+WW';
$hscheme{'9'} = 'A1+M2+M3';
$hscheme{'10'} = 'A1+M2+M3+WW';


#define TCP Connection (1) or USB device (0)
my $connectionType = "usb";

######################################################################################
sub VCONTROL300_1ByteUParse($$);
#sub VCONTROL300_1ByteU2Parse($$);
sub VCONTROL300_1ByteSParse($$);
sub VCONTROL300_2ByteSParse($$);
sub VCONTROL300_2ByteUParse($$$);
sub VCONTROL300_1ByteHexParse($);
sub VCONTROL300_2ByteHexParse($);
#sub VCONTROL300_2BytePercentParse($$);
sub VCONTROL300_4ByteParse($$);
sub VCONTROL300_9ByteParse($$);
sub VCONTROL300_TimerParse($);
sub VCONTROL300_StateParse($);
sub VCONTROL300_ValveParse($); #Art Pumpenventil
sub VCONTROL300_hschemeParse($); # Art Heizkreiswarmwasserschema
sub VCONTROL300_ModusParse($);
sub VCONTROL300_ErrorParse($$);
sub VCONTROL300_DateParse($);
sub VCONTROL300_1ByteUConv($$);
sub VCONTROL300_1ByteSConv($$);
sub VCONTROL300_2ByteUConv($$);
sub VCONTROL300_2ByteSConv($$);
sub VCONTROL300_DateConv($);
sub VCONTROL300_StateConv($);
sub VCONTROL300_ModeConv($);
sub VCONTROL300_ValveConv($);  # Art Pumpenventil
sub VCONTROL300_hschemeConv($); #Art Heizkreiswarmwasserschema
sub VCONTROL300_TimerConv($$);
#sub VCONTROL300_RegisterConv($);
sub VCONTROL300_Read($);
#sub VCONTROL300_Ready($);
sub VCONTROL300_Parse($$$);
sub VCONTROL300_DoInit($$);
sub VCONTROL300_Poll($);
sub VCONTROL300_CmdConfig(\@$$);
sub VCONTROL300_SendCommand($$$$);
sub VCONTROL300_ReadAnswer($$);
sub VCONTROL300_DoUpdate($);
sub VCONTROL300_UpdateDone($);
sub VCONTROL300_SendToDevice($$);
sub VCONTROL300_ReadFromDevice($);
sub VCONTROL300_ExpectFromDevice($$$);
sub VCONTROL300_GetReturnLength($$);
sub VCONTROL300_addSetParameterToList($$$$);
sub VCONTROL300_DeleteInternal($$);
sub VCONTROL300_SetInternal($$$);
sub VCONTROL300_readingsUpdateByName($$$);
sub VCONTROL300_setDayHash($$);

sub VCONTROL300_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  #$hash->{ReadFn}  = "VCONTROL300_Read";
  #$hash->{WriteFn} = "VCONTROL300_Write";
  #$hash->{ReadyFn} = "VCONTROL300_Ready";
  $hash->{DefFn}   = "VCONTROL300_Define";
  $hash->{UndefFn} = "VCONTROL300_Undef";
  $hash->{SetFn}   = "VCONTROL300_Set";
  $hash->{GetFn}   = "VCONTROL300_Get";
  $hash->{StateFn} = "VCONTROL300_SetState";
  $hash->{ShutdownFn} = "VCONTROL300_Shutdown";
  #$hash->{AttrList}  = "disable:0,1 init_every_poll:0,1 update_only_changes:0,1 setList closedev:0,1 ". $readingFnAttributes;
  $hash->{AttrList}  = "disable:0,1 updateOnlyChanges:0,1 vitotronicType:".TYPE_200_WO1X.",".TYPE_200_KWX.",".TYPE_200_HOXX.",".TYPE_200_HOE3." setList cumulationSuffixToday cumulationSuffixTodayStart cumulationSuffixYesterday ". $readingFnAttributes;
}

#####################################
# define <name> VIESSMANN <port> <command_config> [<interval>]
#####################################

sub VCONTROL300_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	#my $po;

	if (@a != 4 && @a != 5 && @a != 6 && @a != 7) {
		my $msg = "wrong syntax: define <name> VCONTROL300 <port> <command_config> [<interval>] [<protocol>] [<protocolparam>]";
		Log3 undef, 2, $msg;
		return $msg;
	}

	my $devName = $a[0];
	my $dev = $a[2];

	#Determine if USB device or TCP Connection is used
	#if (index($dev, ':') >= 0) {	#Does not work for /dev/<USB Device with ":" in name>
	if (index($dev, '/') == -1) {
    #####################################
		###TCP Connection
    #####################################
		Log3 $devName, 2,"VCONTROL300: Using TCP device";
		$connectionType = "tcp";
	}
	else {
    #####################################
		###USB
    #####################################
		Log3 $devName, 2,"VCONTROL300: Using USB device";
		$connectionType = "usb";

		if (index($dev, '@') == -1) {
			$dev=$dev."\@4800,8,E,2";
		}
	}

  #####################################
  #schauen welches protocol verwendet wird.
  #####################################
  if($a[5]){
     my $protocol = lc($a[5]);
	 if ($protocol eq "300") {
		$hash->{PROTOCOL} = PROTOCOL_300;
	 }
	 elsif ($protocol eq "kw") {
		$hash->{PROTOCOL} = PROTOCOL_KW;
	}
  }
  else {
     $hash->{PROTOCOL} = $defaultProtocol;
  }


  #####################################
  #load config_file
  #####################################
  if($a[3]){
     $command_config_file = $a[3];
     my ($error, @cmdconfigfilecontent) = FileRead($command_config_file);
     return $error if $error;
     VCONTROL300_CmdConfig(@cmdconfigfilecontent,$hash,$command_config_file);
  }

  #####################################
  #use configured Pollinterval if given
  #####################################
  if($a[4]){
     $hash->{INTERVAL} = $a[4];
  }
  else {
     $hash->{INTERVAL} = $defaultPollInterval;
  }

  Log3($devName, 3, "VCONTROL300: Using protocol $hash->{PROTOCOL}");

  $hash->{STATE} = "defined";
  $hash->{DeviceName} = $dev;

	#set Internal Timer
	my $timer = gettimeofday()+1;
	Log3($devName, 5, "VCONTROL300: Set InternalTimer to $timer");

	InternalTimer($timer, "VCONTROL300_Poll", $hash, 0);

  return undef;
}

#####################################
sub VCONTROL300_Undef($$)
#####################################
{
  my ($hash, $arg) = @_;
  my $devName = $hash->{NAME};

  Log3($devName, 5, "VCONTROL300: DEBUG VCONTROL300_Undef() entry");

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
}

#####################################
sub VCONTROL300_Poll($)
#####################################
{
	my ($hash) = @_;
	my $devName = $hash->{NAME};
	my $type = AttrVal($devName, "vitotronicType", "");

	Log3($devName, 5, "VCONTROL300: DEBUG VCONTROL300_Poll() entry");
	Log3($devName, 4, "VCONTROL300: fetched attr 'vitotronicType=$type'");


	if (%mapping_operationstate_hash) {
		Log3($devName, 4, "VCONTROL300: Notice! Operation mode mapping by vitotronicType is overwritten by given configuration MAPPING, OPERATIONSTATE, KEY, TEXTVALUE entries");
		%modus = %mapping_operationstate_hash;
	} else {
		if ($type eq TYPE_200_KWX) {
			@mode = @mode_200_KWx;
			%modus = %modus_200_KWx;
		}
		elsif ($type eq TYPE_200_HOXX) {
			@mode = @mode_200_HOxx;
			%modus = %modus_200_HOxx;
		}
		elsif ($type eq TYPE_200_HOE3) {
			@mode = @mode_200_HOE3;
			%modus = %modus_200_HOE3;
		}
                elsif ($type eq TYPE_200_WO1X) {
			@mode = @mode_200_WO1x;
			%modus = %modus_200_WO1x;
		}
		else {
			Log3($devName, 1, "VCONTROL300: attr 'vitotronicType' not set correctly, using internal default value '200_HOxx' which might not match to your heater!");
			@mode = @mode_200_HOxx;
			%modus = %modus_200_HOxx;
		}
	}

	#global Module Trigger that Polling is started
	if( AttrVal($devName, "disable", 0 ) == 1 )
	{
	  $poll_now = POLL_DISABLED;
	  Log3 $devName, 5, "VCONTROL300: Polling disabled!";
	}
	else
	{
	  $poll_now = POLL_ENABLED;
          Log3 $devName, 5, "VCONTROL300: Polling enabled!";
	}

	#Immediately set the timer for the next poll
	#$poll_duration = gettimeofday();
	my $timer = gettimeofday()+$hash->{INTERVAL};
	Log3($devName, 5, "VCONTROL300: DEBUG VCONTROL300_Poll() Set InternalTimer to $timer");
	InternalTimer($timer, "VCONTROL300_Poll", $hash, 0);

	#Log3 $devName, 4, "VCONTROL300: Start of poll!";

        if ($get_config_now eq GET_CONFIG_ACTIVE) {
		$get_config_now = GET_CONFIG_PAUSED;
		my ($error, @cmdconfigfilecontent) = FileRead($command_config_file);
    return $error if $error;
    VCONTROL300_CmdConfig(@cmdconfigfilecontent,$hash,$command_config_file);
		#return;
	}

	if ($set_values_now eq SET_VALUES_ACTIVE) {
		$set_values_now = SET_VALUES_PAUSED;
	}

	if ($get_timer_now eq GET_TIMER_ACTIVE) {
		$get_timer_now = GET_TIMER_PAUSED;
		#@current_cmd_list = @timer_cmd_list;
		%current_cmd_hash = %timer_cmd_hash;
	}
	else {
		#@current_cmd_list = @poll_cmd_list;
		%current_cmd_hash = %poll_cmd_hash;
	}

	#Init the used device/port
	#VCONTROL300_DoInit($devName,$hash);

	$hash->{helper}{RUNNING_PID} = BlockingCall("VCONTROL300_DoUpdate", $devName,"VCONTROL300_UpdateDone",10,"VCONTROL300_UpdateAborted",$devName) unless(exists($hash->{helper}{RUNNING_PID}));
}

#####################################
sub VCONTROL300_Shutdown($)
#####################################
{
  my ($hash) = @_;
  return undef;
}

#####################################
sub VCONTROL300_SetState($$$$)
#####################################
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}


#####################################
sub VCONTROL300_DoInit($$)
#####################################
{
  my ($devName,$hash) = @_;

  #####################################
  #Close Device to initialize properly
  #####################################
  delete $hash->{USBDev};
  delete $hash->{FD};
  DevIo_CloseDev($hash);


  if ($connectionType eq "usb") {
     #Log3 $devName, 2,"VCONTROL300: Using USB device";
	 Log3 $devName, 3,"VCONTROL300: USB connection opened";

  }
  else {
	#Log3 $devName, 2,"VCONTROL300: Using TCP device";
	Log3 $devName, 3,"VCONTROL300: TCP connection opened";
	#DevIo_CloseDev($hash);
	#DevIo_OpenDev($hash, 0, "");
  }

  DevIo_OpenDev($hash, 0, "");

  #$hash->{STATE} = "Connected";
  #Log3 $devName, 3,"VCONTROL300: Connected";

  return undef;
}

#####################################
sub VCONTROL300_DoUpdate($)
#####################################
{
	my ($name) = @_;
	my $hash = $defs{$name};
        my $devName = $hash->{NAME};
	#my $retryCount=0;

  #####################################
	#Init the used device/port
  #####################################
	VCONTROL300_DoInit($name,$hash);

	Log3($devName, 5, "VCONTROL300: DEBUG VCONTROL300_DoUpdate() entry");
	Log3 $name, 4, "VCONTROL300: Start of update...";

	BlockingInformParent("VCONTROL300_SetInternal",[$name,"UPDATESTATUS","ACTIVE"],0);
	BlockingInformParent("VCONTROL300_readingsUpdateByName",[$name,"UpdateStatus","Active"],0);


	#Iterate all set commands
	#if (@set_cmd_list_values) {
	if (%set_cmd_hash_values) {
		Log3 $name, 4, "VCONTROL300: Start of set values...";

		my $set_retryCount=0;
		my $set_duration=gettimeofday();

		#Auf ein SyncByte warten
		my $hexline = "";
		my $nSyncByteRetryCount=0;
		while(1) {
			if ($nSyncByteRetryCount>10) { last; }
			my $retry=1;
			Log3 $name, 4,"VCONTROL300: Waiting for sync byte...";
			#VCONTROL300_SendToDevice($hash,pack('H*', "04"));
			#my $mybuf = VCONTROL300_ReadFromDevice($hash);
			my $mybuf = VCONTROL300_ExpectFromDevice($hash,pack('H*', "04"),10);
			if ($mybuf) {
				$hexline = unpack('H*', $mybuf);
				if ($hexline eq "05") {
					Log3 $name, 4,"VCONTROL300: Received sync byte!";
					$retry=0;
					last;
				}
			}


			if ($retry==1) {
				sleep(1);
				$nSyncByteRetryCount++;
			}
		}


		if ($hexline eq "05") {
			my $init_status="error";
			my $nInitByteRetryCount=0;
			if ($hash->{PROTOCOL} eq PROTOCOL_300) {
				#jetzt das init flag schicken
				my $ret = "";
				while(1) {
					if ($nInitByteRetryCount>10) {last;}
					my $retry=1;
					Log3 $name, 4,"VCONTROL300: Waiting for init byte...";
					#VCONTROL300_SendToDevice($hash,pack('H*', "160000"));
					#my $mybuf = VCONTROL300_ReadFromDevice($hash);
					my $mybuf = VCONTROL300_ExpectFromDevice($hash,pack('H*', "160000"),10);
					if ($mybuf) {
						$ret = unpack('H*', $mybuf);
						if ($ret eq "06") {
							Log3 $name, 4,"VCONTROL300: Received init byte!";
							$init_status="ok";
							$retry=0;
							last;
						}
					}


					if ($retry==1) {
						sleep(1);
						$nInitByteRetryCount++;
					}
				}

				#VCONTROL300_SendToDevice($name,pack('H*', "160000"));
				#my $ret = unpack('H*', VCONTROL300_ReadFromDevice($name));
				#if ($ret eq "06") {
				#$init_status="ok";
				#}
			}
			else {
				$init_status="ok";
			}

			Log3 $name, 4,"VCONTROL300: Init status: '$init_status'!";

			if ($init_status eq "ok") {
				my $removeprefix="false";
				#my $cmdcount = @set_cmd_list_values;
				#my $element =0;
				#while ($element<$cmdcount) {
				foreach my $set_cmd_key (keys %set_cmd_hash_values) {
					my @set_cmd_hash_value = @{$set_cmd_hash_values{$set_cmd_key}};
					my $address = $set_cmd_hash_value[0];
					#my $address = $set_cmd_list_values[$element][0];
					#my $data = "";
					#if (length($address)>4) {
					#	$data = substr($address,4);
					#}
					#else {
					my $data = $set_cmd_hash_value[1];
					#}
					my $datalength = $set_cmd_hash_value[2];
					#my $datalength = $set_cmd_list_values[$element][2];
					my $recv_error="false";

          #####################################
					#300 Protokoll
          #####################################
					if ($hash->{PROTOCOL} eq PROTOCOL_300) {
						my $send_telegramstart = "41";
						my $send_telegramlength = sprintf("%02X",5+hex($datalength));
						my $send_type1 = "00"; #Anfrage
						my $send_type2 = "02"; #WriteData
						my $send_address1 = substr($address,0,2);
						my $send_address2 = substr($address,2,2);
						my $send_datalength = $datalength;
						my $send_data = $data;
						my $send_checksum = (hex($send_telegramlength)+hex($send_type1)+hex($send_type2)+hex($send_address1)+hex($send_address2)+hex($send_datalength));
						for (my $i=0;$i<(hex($send_datalength)*2);$i+=2) {
							my $send_data_part = hex(substr($send_data,$i,2));
							#Log3 $name, 5,"VCONTROL300: send_data_part = ".$send_data_part;
							$send_checksum += $send_data_part;
						}
						$send_checksum = sprintf("%02X", $send_checksum%256);

						my $send_telegram = $send_telegramstart.$send_telegramlength.$send_type1.$send_type2.$send_address1.$send_address2.$send_datalength.$send_data.$send_checksum;

						Log3 $name, 4, "VCONTROL300: Set value $send_telegram";

						eval {
							#VCONTROL300_SendCommand($name,$hash,"false",$send_telegram);
							#my $recv_message = VCONTROL300_ReadAnswer($name,$hash);
							my $recv_message = VCONTROL300_ExpectCommandAnswer($name,$hash,"false",$send_telegram);

							my $recv_status = substr($recv_message,0,2);
							if ($recv_status eq "06") {
									$recv_message = substr($recv_message,2);
									my $recv_message_length = 8;
									#my $recv_message = VCONTROL300_ReadAnswer($name,$hash);
									while (length($recv_message) < ($recv_message_length*2)) {
										my $recv_message_part = VCONTROL300_ReadAnswer($name,$hash);
										$recv_message = $recv_message.$recv_message_part;
										Log3 $name, 5,"VCONTROL300: Received ".(length($recv_message)/2)." of ".($recv_message_length)." bytes of response";
									}

							}
							elsif ($recv_status eq "15") {
								Log3 $name, 2,"VCONTROL300: Error while reading response byte on setting value for parameter $send_address1$send_address2 (Status 0x$recv_status): Retry $set_retryCount!!!";
								$recv_error="true";
							}
						};
						if ($@) {
							Log3 $name, 2,"VCONTROL300: Error while setting value for parameter $send_address1$send_address2: Retry $set_retryCount!!!";
							$recv_error="true";
							print $@->what;
						}
					}
          #####################################
					#KW Protokoll
          #####################################
					else {
						my $send_startbyte = "01";
						my $send_type = "F4";
						my $send_address = $address;
						my $send_datalength = $datalength;
						my $send_data = $data;
						my $send_telegram = $send_startbyte.$send_type.$send_address.$send_datalength.$send_data;

						Log3 $name, 4, "VCONTROL300: Set value $send_telegram";

						eval {
							#VCONTROL300_SendCommand($name,$hash,$removeprefix,$send_telegram);
							#my $recv_status = VCONTROL300_ReadAnswer($name,$hash);
							my $recv_status = VCONTROL300_ExpectCommandAnswer($name,$hash,$removeprefix,$send_telegram);

							if ($recv_status eq "00") {
								#Log3 $name, 2,"VCONTROL300: Error while setting value for parameter $send_address (Status 0x$recv_status): Retry $set_retryCount!!!";
								#$recv_error="true";
								Log3 $name, 5,"VCONTROL300: Received response";
							}
							else {
								Log3 $name, 2,"VCONTROL300: Error while reading response byte on setting value for parameter $address (Status 0x$recv_status): Retry $set_retryCount!!!";
								$recv_error="true";
							}
						};
						if ($@) {
							Log3 $name, 2,"VCONTROL300: Error while setting value for parameter $address: Retry $set_retryCount!!!";
							$recv_error="true";
							print $@->what;
						}

						$removeprefix="true";
					}

					if ($recv_error eq "true") {
						if ($set_retryCount>3) {
							$set_retryCount=0;
							Log3 $name, 2,"VCONTROL300: Retry limit for setting value for parameter $address reached! Aborting!";
							#$element++;
						}
						else {
							$set_retryCount++;
							#Log3 $name, 2,"VCONTROL300: Error while setting value for parameter $address : Retry $set_retryCount!!!";
							redo;
						}
					}
					else {
						$set_retryCount=0;
						#$element++;
					}
				}
			}
			else {
				Log3 $name, 4,"VCONTROL300: Did not receive init byte after $nInitByteRetryCount retries";
			}
		}
		else {
			Log3 $name, 4,"VCONTROL300: Did not receive sync byte after $nSyncByteRetryCount retries!'";
		}

		$set_duration = sprintf("%.2f", (gettimeofday() - $set_duration));
		VCONTROL300_SetInternal($name,"DURATION",$set_duration);
		Log3 $name, 4, "VCONTROL300: End of setting values! Duration: $set_duration";
	}

	#And now do the polling if enabled
	if ($poll_now==POLL_ENABLED) {
		Log3 $name, 4, "VCONTROL300: Start of polling values...";

		my $poll_retryCount=0;
		my $poll_duration=gettimeofday();

		#Auf ein SyncByte warten
		my $hexline = "";
		my $nSyncByteRetryCount=0;
		while(1) {
			if ($nSyncByteRetryCount>10) {last;}
			my $retry=1;
			Log3 $name, 4,"VCONTROL300: Waiting for sync byte...";
			#VCONTROL300_SendToDevice($hash,pack('H*', "04"));
			#my $mybuf = VCONTROL300_ReadFromDevice($hash);
			my $mybuf = VCONTROL300_ExpectFromDevice($hash,pack('H*', "04"),10);
			#Log3 $name, 4,"VCONTROL300: buf '$mybuf'!";
			if ($mybuf) {
				$hexline = unpack('H*', $mybuf);
				if ($hexline eq "05") {
					Log3 $name, 4,"VCONTROL300: Received sync byte!";
					$retry=0;
					last;
				}
			}


			if ($retry==1) {
				sleep(1);
				$nSyncByteRetryCount++;
			}
		}


		if ($hexline eq "05") {
			#Jetzt mal alle Poll Commands durchlaufen
			my $init_status="error";
			my $nInitByteRetryCount=0;
			if ($hash->{PROTOCOL} eq PROTOCOL_300) {
				#jetzt das init flag schicken
				my $ret = "";
				while(1) {
					if ($nInitByteRetryCount>10) {last;}
					my $retry=1;
					Log3 $name, 4,"VCONTROL300: Waiting for init byte...";
					#VCONTROL300_SendToDevice($hash,pack('H*', "160000"));
					#my $mybuf = VCONTROL300_ReadFromDevice($hash);
					my $mybuf = VCONTROL300_ExpectFromDevice($hash,pack('H*', "160000"),10);
					if ($mybuf) {
						$ret = unpack('H*', $mybuf);
						if ($ret eq "06") {
							Log3 $name, 4,"VCONTROL300: Received init byte!";
							$init_status="ok";
							$retry=0;
							last;
						}
					}


					if ($retry==1) {
						sleep(1);
						$nInitByteRetryCount++;
					}
				}

				#VCONTROL300_SendToDevice($name,pack('H*', "160000"));
				#my $ret = unpack('H*', VCONTROL300_ReadFromDevice($name));
				#if ($ret eq "06") {
				#	$init_status="ok";
				#}
			}
			else {
				$init_status="ok";
			}

			Log3 $name, 4,"VCONTROL300: Init status: '$init_status'!";

			if ($init_status eq "ok") {
				my $removeprefix="false";
				#my $cmdcount = @current_cmd_list;
				#my $element =0;
				#while ($element<$cmdcount) {
				foreach my $set_cmd_key (keys %current_cmd_hash) {
					my @current_cmd = @{$current_cmd_hash{$set_cmd_key}};

					my $address = $current_cmd[1];
					my $receive_len = VCONTROL300_GetReturnLength($hash,$current_cmd[2]);

					#my $address = $current_cmd_list[$element][1];
					#my $receive_len = VCONTROL300_GetReturnLength($hash,$current_cmd_list[$element][2]);
					my $recv_error="false";
					#Log3 $name, 5,"VCONTROL300: receive_len $receive_len";

					if ($hash->{PROTOCOL} eq PROTOCOL_300) {
						#Jetzt mal eine Anfrage senden
						my $send_telegramstart = "41";
						my $send_telegramlength = "05";
						my $send_type1 = "00"; #Anfrage
						my $send_type2 = "01"; #ReadData
						my $send_address1 = substr($address,0,2);
						my $send_address2 = substr($address,2,2);
						my $send_datalength = sprintf("%02X",$receive_len);
						my $send_checksum = (hex($send_telegramlength)+hex($send_type1)+hex($send_type2)+hex($send_address1)+hex($send_address2)+hex($send_datalength));
						$send_checksum = sprintf("%02X", $send_checksum%256);

						my $send_telegram = $send_telegramstart.$send_telegramlength.$send_type1.$send_type2.$send_address1.$send_address2.$send_datalength.$send_checksum;

						#Log3 $name, 5,"VCONTROL300: send_checksum $send_checksum";
						#Log3 $name, 5,"VCONTROL300: Set send_telegram $send_telegram";


						eval {
							#VCONTROL300_SendCommand($name,$hash,"false",$send_telegram);
							#my $recv_message = VCONTROL300_ReadAnswer($name,$hash);
							my $recv_message = VCONTROL300_ExpectCommandAnswer($name,$hash,"false",$send_telegram);

							my $recv_status = substr($recv_message,0,2);
							if ($recv_status eq "06") {
								$recv_message = substr($recv_message,2);
								my $recv_message_length = 8+$receive_len;
								#my $recv_message_length = 8+$receive_len;
								#my $recv_message = VCONTROL300_ReadAnswer($name,$hash);
								while (length($recv_message) < ($recv_message_length*2)) {
									my $recv_message_part = VCONTROL300_ReadAnswer($name,$hash);
									$recv_message = $recv_message.$recv_message_part;
									Log3 $name, 5,"VCONTROL300: Received ".(length($recv_message)/2)." of ".($recv_message_length)." bytes";
									Log3 $name, 5,"VCONTROL300: DEBUGGING Received data are recv_message: $recv_message";

									if (length($recv_message_part)==0) {
										Log3 $name, 2,"VCONTROL300: Error while requesting data! Length of received data was 0!!!";
										$recv_error="true";
										last;
									}

									if (length($recv_message)==6) {
										my $type = substr($recv_message,4,2);
										if ($type eq "03") {
											Log3 $name, 2,"VCONTROL300: Error while requesting data! Maybe address '$send_address1$send_address2' or expected data length '$receive_len' is wrong!!!";
											$recv_error="true";
										}
									}
								}

								if ($recv_error eq "false") {
									#Log3 $name, 5,"VCONTROL300: recv_message $recv_message";

									my $recv_telegramstart = substr($recv_message,0,2);
									my $recv_telegramlength = substr($recv_message,2,2);
									my $recv_type1 = substr($recv_message,4,2); #Antwort
									my $recv_type2 = substr($recv_message,6,2); #ReadData
									my $recv_address1 = substr($recv_message,8,2);
									my $recv_address2 = substr($recv_message,10,2);
									my $recv_datalength = substr($recv_message,12,2);
									my $recv_data = substr($recv_message,14,hex($recv_datalength)*2);
									my $recv_checksum = substr($recv_message,14+(hex($recv_datalength)*2),2);

									my $recv_checksum_calc = hex($recv_telegramlength)+hex($recv_type1)+hex($recv_type2)+hex($recv_address1)+hex($recv_address2)+hex($recv_datalength);
									for (my $i=0;$i<(hex($recv_datalength)*2);$i+=2) {
										my $recv_data_part = hex(substr($recv_data,$i,2));
										#Log3 $name, 5,"VCONTROL300: VCONTROL300_Read recv_data_part = ".$recv_data_part;
										$recv_checksum_calc += $recv_data_part;
									}
									$recv_checksum_calc = sprintf("%02X", $recv_checksum_calc%256);

									#Log3 $name, 5,"VCONTROL300: VCONTROL300_Read recv_checksum = $recv_checksum";
									#Log3 $name, 5,"VCONTROL300: VCONTROL300_Read recv_checksum_calc = ".sprintf("%02X", $recv_checksum_calc);

									if (($recv_telegramlength eq sprintf("%02X",5+$receive_len))&&(($recv_type1 eq "01")||($recv_type1 eq "03"))&&($recv_type2 eq "01")&&
									#if (($recv_status eq "06")&&($recv_telegramlength eq sprintf("%02X",5+$receive_len))&&(($recv_type1 eq "01"))&&($recv_type2 eq "01")&&
										($recv_address1 eq $send_address1)&&($recv_address2 eq $send_address2)&&($recv_datalength eq $send_datalength)&&
										($recv_checksum eq $recv_checksum_calc)) {
										#VCONTROL300_Parse($hash,$element,$recv_data,0);
										VCONTROL300_Parse($hash,$set_cmd_key,$recv_data);
									}
									else {
										Log3 $name, 2,"VCONTROL300: Error while reading parameter $recv_address1$recv_address2 : Retry $poll_retryCount!!!";
										$recv_error="true";
									}
								}
							}
							elsif ($recv_status eq "15") {
								Log3 $name, 2,"VCONTROL300: Error while sending command for parameter $send_address1$send_address2 (Status 0x$recv_status) : Retry $poll_retryCount!!!";
								$recv_error="true";
							}
						};
						if ($@) {
							Log3 $name, 2,"VCONTROL300: Error while reading parameter $send_address1$send_address2 : Retry $poll_retryCount!!!";
							$recv_error="true";
							print $@->what;
						}

						if ($recv_error eq "true") {
							if ($poll_retryCount>3) {
								$poll_retryCount=0;
								#$element++;
								Log3 $name, 2,"VCONTROL300: Retry limit for parameter $send_address1$send_address2 reached! Aborting!";
							}
							else {
								$poll_retryCount++;
								redo;
							}
						}
						else {
							$poll_retryCount=0;
							#$element++;
						}
					}
					else {
						my $recv_error_syncbyte="false";
						my $send_startbyte = "01";
						my $send_type = "F7";
						my $send_datalength = sprintf("%02X",$receive_len);
						my $send_telegram = $send_startbyte.$send_type.$address.$send_datalength;

						Log3 $name, 5,"VCONTROL300: Set sendstr $send_telegram";

						my $data;

						eval {
							#VCONTROL300_SendCommand($name,$hash,$removeprefix,$send_telegram);
							#my $data = VCONTROL300_ReadAnswer($name,$hash);
							$data = VCONTROL300_ExpectCommandAnswer($name,$hash,$removeprefix,$send_telegram);
							if ($data eq "05") {
								$recv_error="true";
								$recv_error_syncbyte="true";
							}

							#check if all bytes have been received
							while (length($data) < ($receive_len*2)) {
								Log3 $name, 5,"VCONTROL300: Received ".(length($data)/2)." of ".($receive_len)." bytes";
								Log3 $name, 5,"VCONTROL300: DEBUGGING Received data are data: $data";
								my $datapart = VCONTROL300_ReadAnswer($name,$hash);
								if (($datapart eq "05")||(length($datapart)==0)) {
								#if (length($datapart)==0) {
									$recv_error="true";
									if ($datapart eq "05") {
										$recv_error_syncbyte="true";
									}
									last if (length($datapart)==0);
								}
								$data = $data.$datapart;
							}

							Log3 $name, 5,"VCONTROL300: Data '$data'";

							if ($recv_error eq "false") {
								if (length($data)>0) {
									VCONTROL300_Parse($hash,$set_cmd_key,$data);
								}
							}
							else {
								if ($recv_error_syncbyte eq "true") {
									Log3 $name, 2,"VCONTROL300: Warning while reading parameter $address. Maybe value is a sync byte? : Retry $poll_retryCount!!!";
								}
								else {
									Log3 $name, 2,"VCONTROL300: Error while reading parameter $address : Retry $poll_retryCount!!!";
								}
							}
						};
						if ($@) {
							Log3 $name, 2,"VCONTROL300: Error while reading parameter $address : Retry $poll_retryCount!!!";
							$recv_error="true";
							print $@->what;
						}

						$removeprefix="true";

						if ($recv_error eq "true") {
							if ($poll_retryCount>3) {
								$poll_retryCount=0;

								if (($recv_error_syncbyte eq "true")&&(length($data)>0)){
									Log3 $name, 2,"VCONTROL300: Received value $data for reading parameter $address seems not include a sync byte! Parsing value!";
									VCONTROL300_Parse($hash,$set_cmd_key,$data);
								}
								else {
									Log3 $name, 2,"VCONTROL300: Retry limit for reading parameter $address reached! Aborting!";
								}
								#VCONTROL300_Parse($hash,$set_cmd_key,$data) if (length($data)>0);
								#$element++;
							}
							else {
								$poll_retryCount++;
								#Log3 $name, 2,"VCONTROL300: Error while reading parameter $address : Retry $poll_retryCount!!!";
								redo;
							}
						}
						else {
							$poll_retryCount=0;
							#VCONTROL300_Parse($hash,$set_cmd_key,$data)if (length($data)>0);
							#$element++;
						}
					}
				}
			}
			else {
				Log3 $name, 4,"VCONTROL300: Did not receive init byte after $nInitByteRetryCount retries";
			}
		}
		else {
			Log3 $name, 4,"VCONTROL300: Did not receive sync byte after $nSyncByteRetryCount retries!'";
		}

		$poll_duration = sprintf("%.2f", (gettimeofday() - $poll_duration));
		VCONTROL300_SetInternal($name,"DURATION",$poll_duration);
		Log3 $name, 4, "VCONTROL300: End of polling values! Duration: $poll_duration";
	}



	#verbindung zu machen
	DevIo_CloseDev($hash);

	return $name;
	#return $hash;
}

#####################################
sub VCONTROL300_UpdateDone($)
#####################################
{
	my ($name) = @_;
	my $hash = $defs{$name};

        Log3 $name, 5,"VCONTROL300: DEBUG VCONTROL300_UpdateDone() delete($hash->{helper}{RUNNING_PID})";
	delete($hash->{helper}{RUNNING_PID});

	VCONTROL300_SetInternal($name,"UPDATESTATUS","INACTIVE");
	VCONTROL300_readingsUpdateByName($name,"UpdateStatus","Inactive");

    Log3 $name, 4,"VCONTROL300: Update done!";


	#$hash->{STATE} = "Initialized";

	DevIo_CloseDev($hash);

	if ($connectionType eq "usb") {
		Log3 $name, 3, "VCONTROL300: USB device closed";
	}
	else {
		Log3 $name, 3, "VCONTROL300: TCP connection closed";
	}


	if (($get_timer_now eq GET_TIMER_ACTIVE)||($get_config_now eq GET_CONFIG_ACTIVE)||($set_values_now eq SET_VALUES_ACTIVE)) {
		RemoveInternalTimer($hash);
                Log3 $name, 5,"VCONTROL300: VCONTROL300_UpdateDone() get_timer_now: $get_timer_now";
		VCONTROL300_Poll($hash);
	}
	elsif ($set_values_now eq SET_VALUES_PAUSED) {
		Log3 $name, 5,"VCONTROL300: VCONTROL300_UpdateDone() Undef set_cmd_list_values!";
		#undef @set_cmd_list_values;
		undef %set_cmd_hash_values;
	}
 }

#####################################
sub VCONTROL300_UpdateAborted($)
#####################################
{
	my ($name) = @_;
	my $hash = $defs{$name};

        Log3 $name, 5,"VCONTROL300: DEBUG VCONTROL300_UpdateAborted() delete($hash->{helper}{RUNNING_PID})";
	delete($hash->{helper}{RUNNING_PID});

	VCONTROL300_SetInternal($name,"UPDATESTATUS","INACTIVE");
	VCONTROL300_readingsUpdateByName($name,"UpdateStatus","Inactive");

	Log3 $name, 4,"VCONTROL300: Update aborted!";

	#$hash->{STATE} = "Initialized";

	DevIo_CloseDev($hash);

	if ($connectionType eq "usb") {
		Log3 $name, 2, "VCONTROL300: USB device closed";
	}
	else {
		Log3 $name, 2, "VCONTROL300: TCP connection closed";
	}

	if (($get_timer_now eq GET_TIMER_ACTIVE)||($get_config_now eq GET_CONFIG_ACTIVE)||($set_values_now eq SET_VALUES_ACTIVE)) {
		RemoveInternalTimer($hash);
		VCONTROL300_Poll($hash);
	}
	elsif ($set_values_now eq SET_VALUES_PAUSED) {
		Log3 $name, 5,"VCONTROL300: VCONTROL300_UpdateAborted() Undef set_cmd_list_values!";
		#undef @set_cmd_list_values;
		undef %set_cmd_hash_values;
	}
 }


#####################################
sub VCONTROL300_DeleteInternal($$)
#####################################
{
	my ($devName,$internalName) = @_;
	my $hash = $defs{$devName};

	delete $hash->{$internalName};
}

#####################################
sub VCONTROL300_SetInternal($$$)
#####################################
{
	my ($devName,$internalName,$value) = @_;
	my $hash = $defs{$devName};

	$hash->{$internalName}=$value;
}

#####################################
sub VCONTROL300_SendToDevice($$)
#####################################
{
	my ($hash ,$sendbuf) = @_;
	#my ($devName ,$sendbuf) = @_;
	#my $hash = $defs{$devName};

	#Log3 $devName, 5, "VCONTROL300: sendtodevice '$sendbuf'";

	DevIo_SimpleWrite($hash, $sendbuf, 0);
}

#####################################
sub VCONTROL300_ReadFromDevice($)
#####################################
{
	my ($hash) = @_;
	#my ($devName) = @_;
	#my $hash = $defs{$devName};

	#orig ohne Timeout my $buf = DevIo_SimpleRead($hash);
	#Patch
	my $buf = DevIo_SimpleReadWithTimeout($hash,1);

	#if(!defined($buf) || length($buf) == 0) {
	#	VCONTROL300_DoInit($devName);

	#	$buf = DevIo_SimpleRead($hash);
	#}

	#Log3 $devName, 5, "VCONTROL300: readfromdevice '$buf'";

	return $buf;
}

#####################################
sub VCONTROL300_ExpectFromDevice($$$)
#####################################
{
	my ($hash,$sendbuf,$timeout) = @_;

	my $buf = DevIo_Expect($hash,$sendbuf,$timeout);

	return $buf;
}

#####################################
sub VCONTROL300_SendCommand($$$$)
#####################################
{
	my ($name,$hash,$removeprefix,$sendstr) = @_;

	#Log3 $name, 5, "VCONTROL300: send '$sendstr'";

	if ( $sendstr && $sendstr ne "" ){
		if ($removeprefix eq "true") {
			Log3 $name, 5, "VCONTROL300: Delete prefix 01 of sendstr";
			$sendstr = substr($sendstr,2);
		}

		my $sendbuf = pack('H*', "$sendstr");

		#Send to Device
		Log3 $name, 5, "VCONTROL300: Send $sendstr";
		#VCONTROL300_SendToDevice($name,$sendbuf);
		VCONTROL300_SendToDevice($hash,$sendbuf);
    }
    else { #wenn wir hier reinrutschen ist etwas mit den listen durcheinander geraten, workaround reset der liste und der commands!
       Log3 $name, 5, "VCONTROL300: Sendstr empty!";
       #$poll_now = POLL_PAUSED;
    }
}

#####################################
sub VCONTROL300_ReadAnswer($$)
#####################################
{
	my ($name,$hash) = @_;

	#Read from Device
	#my $mybuf = VCONTROL300_ReadFromDevice($name);
	my $mybuf = VCONTROL300_ReadFromDevice($hash);
	my $hexline = uc(unpack('H*', $mybuf));
    Log3 $name, 5,"VCONTROL300: Read '$hexline'";

	return $hexline;
}

#####################################
sub VCONTROL300_ExpectCommandAnswer($$$$)
#####################################
{
	my ($name,$hash,$removeprefix,$sendstr) = @_;

	if ( $sendstr && $sendstr ne "" ){
		if ($removeprefix eq "true") {
			Log3 $name, 5, "VCONTROL300: Delete prefix 01 of sendstr";
			$sendstr = substr($sendstr,2);
		}

		my $sendbuf = pack('H*', "$sendstr");

		#Send to Device
		Log3 $name, 5, "VCONTROL300: Send $sendstr";

		my $mybuf = VCONTROL300_ExpectFromDevice($hash,$sendbuf,10);
		my $hexline = uc(unpack('H*', $mybuf));
		Log3 $name, 5,"VCONTROL300: Read '$hexline'";

		return $hexline;
   }
  else { #wenn wir hier reinrutschen ist etwas mit den listen durcheinander geraten, workaround reset der liste und der commands!
       Log3 $name, 5, "VCONTROL300: Sendstr empty!";
       #$poll_now = POLL_PAUSED;
    }

	return undef;
}


#####################################
sub VCONTROL300_readingsUpdateByName($$$)
#####################################
{
  my ($devName, $readingName, $readingVal) = @_;
  my $hash = $defs{$devName};
  #Log3 $hash, 5, "VCONTROL300_readingsSingleUpdateByName: Dev:$devName Reading:$readingName Val:$readingVal";
  #readingsBeginUpdate($defs{$devName});
  #readingsBulkUpdate($defs{$devName}, $readingName, $readingVal, 1);
  #readingsEndUpdate($defs{$devName},1);

  readingsSingleUpdate($hash, $readingName, $readingVal, 1);
}

#####################################
sub VCONTROL300_setDayHash($$)
#####################################
{
	my ($valuename,$value) = @_;
	$DayHash{$valuename} = $value;
}

#####################################
sub VCONTROL300_GetReturnLength($$)
#####################################
{
	my ($hash, $cmdtype) = @_;
	my $name = $hash->{NAME};

	#Log3 $hash, 5, "VCONTROL300: $cmdtype";
	Log3($name, 5, "VCONTROL300: DEBUG VCONTROL300_GetReturnLength() entry");

	my $value = 0;

	if (index($cmdtype,"1Byte")==0) {
		$value=1;
	}
	elsif (index($cmdtype,"2Byte")==0) {
		$value=2;
	}
	elsif (index($cmdtype,"4Byte")==0) {
		$value=4;
	}
	elsif (index($cmdtype,"7Byte")==0) {
		$value=7;
	}
	elsif (index($cmdtype,"8Byte")==0) {
		$value=8;
	}
	elsif (index($cmdtype,"9Byte")==0) {
		$value=9;
	}
	#elsif (index($cmdtype,"mode")==0) {
	#	$value=1;
	#}
	elsif (index($cmdtype,"timer")==0) {
		$value=8;
		#$value=168;
		#$value=56;
		#$value=24;
	}
	elsif (index($cmdtype,"date")==0) {
		$value=8;
	}

	return $value;
}


#####################################
sub VCONTROL300_Parse($$$)
#####################################
{
  #my ($hash, $element, $data,$answer) = @_;
  #my ($hash, $setname, $data,$answer) = @_;
  my ($hash, $setname, $data) = @_;

  my $value = "";
  #my $valuename = "";
  my $name = $hash->{NAME};

  Log3($name, 5, "VCONTROL300: DEBUG VCONTROL300_Parse() entry");
  Log3 $name, 5,"VCONTROL300: DEBUGGING VCONTROL300_Parse() data=$data , length=".length($data);
  #if ($answer == 0){
     my @current_cmd = @{$current_cmd_hash{$setname}};
	 my $cmdtype = $current_cmd[2];
	 my $divisor = $current_cmd[3];
	 my $valuename = $current_cmd[4];
	 my $cumulation = $current_cmd[5];

	 #my $cmdtype = $current_cmd_list[$element][2];
	 #my $divisor = $current_cmd_list[$element][3];
	 #my $valuename = $current_cmd_list[$element][4];
	 #my $cumulation = $current_cmd_list[$element][5];

	 if ($cmdtype eq "1ByteU"){
        $value = VCONTROL300_1ByteUParse(substr($data, 0, 2),$divisor) if (length($data) > 1);
     #} elsif ($cmdtype eq "1ByteU2"){
     #   $value = VCONTROL300_1ByteU2Parse(substr($data, 0, 2),$divisor) if (length($data) > 1);
     } elsif ($cmdtype eq "1ByteS"){
        $value = VCONTROL300_1ByteSParse(substr($data, 0, 2),$divisor) if (length($data) > 1);
     } elsif ($cmdtype eq "2ByteS"){
        $value = VCONTROL300_2ByteSParse($data,$divisor) if (length($data) > 3);
     } elsif ($cmdtype eq "2ByteU"){
        $value = VCONTROL300_2ByteUParse($data,$divisor,"all") if (length($data) > 3);
	 } elsif ($cmdtype eq "2ByteU_1stByte"){
        $value = VCONTROL300_2ByteUParse($data,$divisor,"first") if (length($data) > 3);
	 } elsif ($cmdtype eq "2ByteU_2ndByte"){
        $value = VCONTROL300_2ByteUParse($data,$divisor,"second") if (length($data) > 3);
     } elsif ($cmdtype eq "1ByteH"){
        $value = VCONTROL300_1ByteHexParse($data) if (length($data) > 1);
     } elsif ($cmdtype eq "2ByteH"){
        $value = VCONTROL300_2ByteHexParse($data) if (length($data) > 3);
     #} elsif ($cmdtype eq "2BytePercent"){
     #   $value = VCONTROL300_2BytePercentParse($data,$divisor) if (length($data) > 1);
     } elsif ($cmdtype eq "4Byte"){
        $value = VCONTROL300_4ByteParse($data,$divisor) if (length($data) > 7);
     } elsif ($cmdtype eq "9Byte"){
        $value = VCONTROL300_9ByteParse($data,$divisor) if (length($data) > 17);
     } elsif ($cmdtype eq "timer"){
        #Log3 undef, 0, "VCONTROL300: TimerHexline: $data";
		$value = VCONTROL300_TimerParse($data) if (length($data) > 7);
     } elsif ($cmdtype eq "date"){
        $value = VCONTROL300_DateParse($data) if (length($data) > 7);
     } else {
		Log3 $name, 2, "VCONTROL300: FixMe - Catched unknown parsing method '$cmdtype' in VCONTROL300_Parse() but should be catched in VCONTROL300_CmdConfig()";
     }

     #this will be the name of the Reading
     #$valuename = $current_cmd_list[$element][4];
     Log3 $name, 5,"VCONTROL300: Parsed '$valuename : $value'";

     return $name if ($value eq "");

	if ( $divisor =~ /^\d+$/ && $divisor >99){
		$value = sprintf("%.2f", $value);
	}

     #if (  $cmdtype
     #   && $cmdtype ne "mode"
     #   && $cmdtype ne "timer"
     #   && $divisor ne "state"
     #   && $divisor >  99){
     #     $value = sprintf("%.2f", $value);
	#	  }

     #TODO config Min and Max Values ????
     #if ( substr($valuename,0,4) eq "Temp"){
     #   if ( $value < -30 || $value > 199 ){
     #      $value = ReadingsVal($name,"$valuename",0);
     #   }
     #}

     #get systemtime
     my ($sec,$min,$hour,$day,$mon,$year) = localtime;
     $year+=1900;
     $mon = $mon+1;
     my $plotmonth = $mon;
     my $plotmday = $day;
     my $plothour = $hour;
     my $plotmin = $min;
     my $plotsec = $sec;
     if ($mon < 10) {$plotmonth = "0$mon"};
     if ($day < 10) {$plotmday = "0$day"};
     if ($hour < 10) {$plothour = "0$hour"};
     if ($min < 10) {$plotmin = "0$min"};
     if ($sec < 10) {$plotsec = "0$sec"};
	  my $systime="$year-$plotmonth-$plotmday"."_"."$plothour:$plotmin:$plotsec";

	  my $updateOnlyChanges = AttrVal($name, "updateOnlyChanges", "0");
	  if ( $updateOnlyChanges == 0 || ($updateOnlyChanges == 1 && (ReadingsVal($name,$valuename,"") ne $value))) {
			Log3 $name, 5,"VCONTROL300: Update reading '$valuename : $value'";
			BlockingInformParent("VCONTROL300_readingsUpdateByName",[$name,"$valuename",$value],0);
	  }

	  #calculate Kumulation Readings and Day Readings
	  if ($cumulation eq "day"  ){
		my $cumulationSuffixToday = AttrVal($name, "cumulationSuffixToday", "_Today");
		my $cumulationSuffixTodayStart = AttrVal($name, "cumulationSuffixTodayStart", "_TodayStart");
		my $cumulationSuffixYesterday = AttrVal($name, "cumulationSuffixYesterday", "_Yesterday");

		 my $current_value = sprintf("%.2f", $value);
		 my $start_value = ReadingsVal($name,$valuename.$cumulationSuffixTodayStart,$current_value);
		 my $cumulated_value =  sprintf("%.2f",$current_value - $start_value);

		 if ( $updateOnlyChanges == 0 || ($updateOnlyChanges == 1 && (ReadingsVal($name,$valuename.$cumulationSuffixToday,"") ne $cumulated_value))) {
			BlockingInformParent("VCONTROL300_readingsUpdateByName",[$name,$valuename.$cumulationSuffixToday,$cumulated_value],0);
		}

		 #Next Day for this value is reached
		 my $last_day= $DayHash{$valuename};
		 Log3 $name, 5, "VCONTROL300: DEBUG nextday $day <-> $last_day";
		 if ($day != $last_day){
			if ($cumulationSuffixYesterday ne "none") {
				BlockingInformParent("VCONTROL300_readingsUpdateByName",[$name,$valuename.$cumulationSuffixYesterday,$cumulated_value],0);
			}
			BlockingInformParent("VCONTROL300_setDayHash",[$valuename,$day],0);
		 }

		 if (($day != $last_day)||(ReadingsVal($name,$valuename.$cumulationSuffixTodayStart,"") eq "")) {
			BlockingInformParent("VCONTROL300_readingsUpdateByName",[$name,$valuename.$cumulationSuffixTodayStart,$current_value],0);
		}
	  }

	  #if all polling commands are send, update Reading UpdateTime
	  #my $all_cmd = @current_cmd_list -1;
	  #if ($element == $all_cmd) {
	  my $last_cmd = (keys %current_cmd_hash)[-1];
          Log3 $name, 5, "VCONTROL300: DEBUG setname: $setname <eq> last_cmd: $last_cmd";
	  if ($setname eq $last_cmd) {
		 BlockingInformParent("VCONTROL300_readingsUpdateByName",[$name,"UpdateTime",$systime],0);
	  }
  #}

  return $name;
}

#####################################
sub VCONTROL300_Set($@)
#####################################
{
	my ($hash, @a) = @_;
	my $devName = $hash->{NAME};
	my $setname = $a[1];
	my $setvalue = (defined $a[2]) ? $a[2] : "";

	my $setListUserDefined = AttrVal($devName, "setList", " ");

	Log3($devName, 5, "VCONTROL300: DEBUG VCONTROL300_Set() entry");

	#Log3 $devName, 0, "VCONTROL300: '".scalar(@setListUserDefined)+"'";

	my @setList;
	if (($setListUserDefined eq " ")) {
		#foreach(@set_cmd_list) {
		#	push(@setList,$$_[4]);
		#}
		foreach my $set_cmd_key (keys %set_cmd_hash) {
			push(@setList,$set_cmd_key);
		}
	}
	else{
		@setList = $setListUserDefined;
	}

	foreach my $key (@setList) {
		#Log3 $devName, 0, "VCONTROL300: '$key'";
		if (index($key,":")<0) {
			my $set_cmd_hash_element = $set_cmd_hash{$key};

			if ($set_cmd_hash_element) {
				my @setcmd = @{$set_cmd_hash_element};
				#Log3 $devName, 0, "VCONTROL300: '@setcmd'";
				if (@setcmd) {
					my $mp = $setcmd[3];
					if ($mp eq "mode") {
						my $modes="";
						foreach (@mode) {
							if (length($modes)>0) {
								$modes.=",";
							}
							$modes .= $_;
						}
						$key .= ":".$modes;
					}
					elsif ($mp eq "state") {
						my $states="";
						foreach (@state) {
							if (length($states)>0) {
								$states.=",";
							}
							$states .= $_;
						}
						$key .= ":".$states;
					}

					#Log3 $devName, 0, "VCONTROL300: '$key'";
				}
			}
		}
	}

	#foreach my $key (@setList) {
	#	Log3 $devName, 0, "VCONTROL300: '$key'";
	#}


	#if (defined($setname)) {
	#	my @setcmd = @{$set_cmd_hash{$setname}};
	#	if (@setcmd) {
	#		my $type = $setcmd[2];
	#		#my $name = $setcmd[4];
	#		if ($type eq "mode") {
	#			$setname .= ":";
	#			my $modes="";
	#			foreach (@mode) {
	#				if (length($modes)>0) {
	#					$modes.=",";
	#				}
	#				$setname .= $_;
	#			}
	#		}
	#	}
	#}


	return "Unknown argument ?, choose one of @setList" if( $setname eq "?");

	VCONTROL300_addSetParameterToList($hash,$setname,$setvalue,0);

	$set_values_now = SET_VALUES_ACTIVE;

	unless(exists($hash->{helper}{RUNNING_PID})) {
		RemoveInternalTimer($hash);
		VCONTROL300_Poll($hash);
	}

	return "";
}

#####################################
sub VCONTROL300_addSetParameterToList($$$$)
#####################################
{
	my ($hash,$arg,$value,$count) = @_;
	my $devName = $hash->{NAME};

	Log3($devName, 5, "VCONTROL300: DEBUG VCONTROL300_addSetParameterToList() entry");
	#Log3 $devName, 0, "VCONTROL300: arg: $arg";

	my $set_cmd_hash_element = $set_cmd_hash{$arg};

	if ($set_cmd_hash_element) {
		my @setcmd = @{$set_cmd_hash_element};
		if (@setcmd) {
			#Log3 $devName, 0, "VCONTROL300: scalar:".scalar(@setcmd);

			my $address = $setcmd[1];
			my $type = $setcmd[2];
			my $multiplicator = $setcmd[3];
			my $setname = $setcmd[4];
			my $nextcmdorday = $setcmd[5];

			#Log3 $devName, 0, "VCONTROL300: address:".$address;

			my $data="";

			if (length($value)>0) {
				if ($type eq "1ByteU"){
				   $data=VCONTROL300_1ByteUConv($value,$multiplicator);
				}
				elsif ($type eq "1ByteUx10"){
				   $data=VCONTROL300_1ByteUConv($value,10);
				}
				elsif ($type eq "1ByteS"){
				   $data=VCONTROL300_1ByteSConv($value,$multiplicator);
				}
				elsif ($type eq "1ByteSx10"){
				   $data=VCONTROL300_1ByteSConv($value,10);
			   }
				elsif ($type eq "2ByteU"){
				   $data=VCONTROL300_2ByteUConv($value,$multiplicator);
				}
				elsif ($type eq "2ByteUx10"){
				   $data=VCONTROL300_2ByteUConv($value,10);
				}
				elsif ($type eq "2ByteS"){
				   $data=VCONTROL300_2ByteSConv($value,$multiplicator);
				}
				elsif ($type eq "2ByteSx10"){
				   $data=VCONTROL300_2ByteSConv($value,10);
				}
				elsif ($type eq "date"){
				  $data=VCONTROL300_DateConv($value);
				}
				#elsif ($type eq "mode"){
				#  $data=VCONTROL300_ModeConv($value);
				#}
			   elsif ($type eq "timer"){
				  $data=VCONTROL300_TimerConv($value,$nextcmdorday);
				  #@get_timer_cmd_list = @timer_cmd_list;
				  #$get_timer_now = GET_TIMER_ACTIVE;
				}
				#elsif ($type eq "Register"){
				#	$set_value=VCONTROL300_RegisterConv($value);
				#	if ($set_value eq "")
				#	{
				#		Log3 $devName, 1, "VCONTROL300: Register falsch eingegeben: $value";
				#	   return "";
				#	}
				#	else {
				#		Log3 $devName, 1, "VCONTROL300: Register gesetzt: $value (01F427$set_value)";
				#	}
				#}
			}

			if (length($address)>4) {
				$data = substr($address,4);
				$address = substr($address,0,4);
			}

			if (length($data)>0) {
				my $datalength = sprintf("%02X",VCONTROL300_GetReturnLength($hash,$type));

				Log3 $devName, 5, "VCONTROL300: Add value '$data' for parameter '$address' to set list!";

				#my @values = ($address,$data,$datalength);
				#push(@set_cmd_list_values,\@values);
				$set_cmd_hash_values{$setname}=[$address,$data,$datalength];
			}
			else {
				Log3 $devName, 2, "VCONTROL300: Error! Set value for parameter '$address' is empty!";
			}

			if (($nextcmdorday ne "-")&&(length($nextcmdorday)>0)&&($count<20)) {
				$count++;
				VCONTROL300_addSetParameterToList($hash,$nextcmdorday,"",$count);
			}
		}
	}
	else {
		Log3 $devName, 2, "VCONTROL300: Error! Set name '$arg' does not exist!";
	}

	return;
}


#####################################
sub VCONTROL300_Get($@)
#####################################
{
  my ($hash, @a) = @_;
  return "No get value specified" if(@a < 2);

  my $devName = $hash->{NAME};
  my $arg = $a[1];
  my $value = (defined $a[2]) ? $a[2] : "";

  Log3($devName, 5, "VCONTROL300: DEBUG VCONTROL300_Get() entry");
  return "Unknown argument ?, choose one of getTimers readConfigFile" if( $arg eq "?");

  if ($arg eq "getTimers" )
  {
	$get_timer_now = GET_TIMER_ACTIVE;

	unless(exists($hash->{helper}{RUNNING_PID})) {
		RemoveInternalTimer($hash);
		VCONTROL300_Poll($hash);
	}

	return "";
  }
  elsif ($arg eq "readConfigFile" )
  {
    $get_config_now = GET_CONFIG_ACTIVE;

	unless(exists($hash->{helper}{RUNNING_PID})) {
		RemoveInternalTimer($hash);
		VCONTROL300_Poll($hash);
	}

	return "";
  }



  #if ($poll_now == POLL_PAUSED ){
  #   @cmd_list = @get_timer_cmd_list;
  #   Log3 $devName, 5, "VCONTROL300: Poll GET!";
  #   RemoveInternalTimer($hash);
  #   VCONTROL300_Poll($hash);
  #}
  #else {
  #   $get_timer_now = GET_TIMER_ACTIVE;
  #}

  #return "Not implemented yet!";
}



#####################################
#####################################
## Load Config
#####################################
#####################################


#####################################
sub VCONTROL300_CmdConfig(\@$$)
#####################################
{

  my($cmdconfigfilecontent_ref,$hash,$cmd_config_file) = @_;
  my $devName = $hash->{NAME};

  Log3($devName, 5, "VCONTROL300: DEBUG VCONTROL300_CmdConfig() entry");
  my ($sec,$min,$hour,$mday,$mon,$year) = localtime;
  my $write_idx=0;


  #undef @poll_cmd_list;
  #undef @set_cmd_list;
  #undef @timer_cmd_list;
  undef %poll_cmd_hash;
  undef %set_cmd_hash;
  undef %timer_cmd_hash;
  undef %mapping_errorstate_hash;
  undef %mapping_operationstate_hash;

  Log3 undef, 3, "VCONTROL300: Opening file '$cmd_config_file'";

  foreach (@$cmdconfigfilecontent_ref)  {
        my $zeile=trim($_);
        Log3 $devName, 5, "VCONTROL300: CmdConfig-Zeile: $zeile";
        if ( length($zeile) > 0 && substr(ltrim($zeile),0,1) ne "#")	# ltrim removes white spaces from the left side of a string
        {
           my @cfgarray = split(",",$zeile);

		   if (scalar(@cfgarray) < 6) {  # each entry in config file needs to have 6 columns!!!
             Log3 $devName, 1,"VCONTROL300: Fault in CmdConfig-Zeile! 6 values expected, but only ".scalar(@cfgarray)." columns found in CFG line ='$zeile'";
           }

           foreach(@cfgarray) {
              $_ = trim($_);
           }

		    my $pollset = $cfgarray[0];
			my $address = $cfgarray[1];
			my $type = $cfgarray[2];
			my $multiplicator = $cfgarray[3];
			my $setname = $cfgarray[4];
			my $nextcmdorday = $cfgarray[5];

           if ($pollset eq "POLL"){
              if ($type ne "1ByteU"
                 #&& $cfgarray[2] ne "1ByteU2"
                 && $type ne "1ByteS"
                 && $type ne "2ByteS"
                 && $type ne "2ByteU"
				 && $type ne "2ByteU_1stByte"
				 && $type ne "2ByteU_2ndByte"
                 && $type ne "1ByteH"
                 && $type ne "2ByteH"
                 #&& $type ne "2BytePercent"
                 && $type ne "4Byte"
				 && $type ne "7Byte"
				 && $type ne "8Byte"
				 && $type ne "9Byte"
                 && $type ne "mode"
                 && $type ne "date"
                 && $type ne "timer"
                 && $type ne "valve"
                 && $type ne "hscheme"
                 ){
                 Log3 $devName, 2, "VCONTROL300: Unknown parsing method '$type' in '$cmd_config_file'";
              }
              else {
                 if ($type eq "timer")
                 {
                    #my @timercmd = ($pollset,$address,$type,$multiplicator,$setname,$nextcmdorday);
                    #push(@timer_cmd_list,\@timercmd);
					$timer_cmd_hash{$setname}=[$pollset,$address,$type,$multiplicator,$setname,$nextcmdorday];
                 }
                 else {
                    #my @pollcmd = ($pollset,$address,$type,$multiplicator,$setname,$nextcmdorday);
                    #push(@poll_cmd_list,\@pollcmd);
					$poll_cmd_hash{$setname}=[$pollset,$address,$type,$multiplicator,$setname,$nextcmdorday];
                    if ($nextcmdorday eq "day"){
                       $DayHash{$setname} = $mday;
                    }
                 }
              }
           }
           elsif ($pollset eq "SET"){
				if (($type eq "timer")
				   && $nextcmdorday ne "MO"
				   && $nextcmdorday ne "DI"
				   && $nextcmdorday ne "MI"
				   && $nextcmdorday ne "DO"
				   && $nextcmdorday ne "FR"
				   && $nextcmdorday ne "SA"
				   && $nextcmdorday ne "SO")
				{
					Log3 $devName, 1, "VCONTROL300: Wrong day '$nextcmdorday' in '$cmd_config_file'";
				}
				else {
				   #if ($type eq "mode") {
						#$setname = $setname.":";

					#	foreach(@mode) {
					#	}
				   #}


				   #my @setcmd = ($pollset,$address,$type,$multiplicator,$setname,$nextcmdorday,$write_idx);
				   #push(@set_cmd_list,\@setcmd);
				   $set_cmd_hash{$setname}=[$pollset,$address,$type,$multiplicator,$setname,$nextcmdorday,$write_idx];
				   $write_idx++;
				}
			}
			elsif ($pollset eq "MAPPING"){
				if ($address eq "ERRORSTATE") {
					# column $type is KEY
					# column $multiplicator is TEXTVALUE
					$mapping_errorstate_hash{$type}=$multiplicator;
				} elsif ($address eq "OPERATIONSTATE") {
					# column $type is KEY
					# column $multiplicator is TEXTVALUE
					$mapping_operationstate_hash{$type}=$multiplicator;
				}
			}
			else {
              Log3 $devName, 2, "VCONTROL300: Unknown command '$pollset' in '$cmd_config_file'";
           }
        }
  };
  Log3 $devName, 3, "VCONTROL300: File '$cmd_config_file' refreshed";
}

###########################################################################
###########################################################################
### PARSE ROUTINES
###########################################################################
###########################################################################

#####################################
sub VCONTROL300_1ByteUParse($$)
#####################################
{
  my ($name) = @_;
  my $hexvalue = shift;
  my $divisor = shift;
  my $retstr="";

  Log3 $name, 5, "VCONTROL300: DEBUGGING VCONTROL300_1ByteUParse() divisor=$divisor | hexvalue=$hexvalue";

  if (!$divisor || length($divisor) == 0 || $divisor eq "state"){
     #$retstr = ($hexvalue eq "00") ? "off" : "on";
	 $retstr = VCONTROL300_StateParse($hexvalue);
  }
  elsif ($divisor eq "mode") {
		$retstr = VCONTROL300_ModeParse($hexvalue);
  }
# Art Pumpenventil
  elsif ($divisor eq "valve") {
		$retstr = VCONTROL300_ValveParse($hexvalue);
  }
# Art hscheme
  elsif ($divisor eq "hscheme") {
		$retstr = VCONTROL300_hschemeParse($hexvalue);
  }
  else{
     #check if divisor is numeric and not 0
     if ( $divisor =~ /^\d+$/ && $divisor != 0){
     	  $retstr = hex($hexvalue)/$divisor;
     }
     else {
     	  Log3 undef, 3, "VCONTROL300: divisor not numeric '$divisor' or 0, it will be ignored";
     	  $retstr = hex($hexvalue)
     }
  }
  return $retstr;
}

#####################################
#sub VCONTROL300_1ByteU2Parse($$)
#{
#	my $hexvalue = shift;
#	my $divisor = shift;

#	return VCONTROL300_1ByteUParse(substr($hexvalue,2,2),$divisor);
#}

#####################################
sub VCONTROL300_1ByteSParse($$)
#####################################
{
  my $hexvalue = shift;
  my $divisor = shift;

  return unpack('c', pack('C',hex($hexvalue)))/$divisor;
}
#####################################
sub VCONTROL300_1ByteHexParse($)
#####################################
{
  my $hexvalue = shift;

  return $hexvalue;
}
#####################################
sub VCONTROL300_2ByteUParse($$$)
#####################################
{
  my $hexvalue = shift;
  my $divisor = shift;
  my $byte = shift;

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_2ByteUParse() with hexvalue=$hexvalue";
  #my $string = "";
  if ($byte eq "all") {
  	return hex(substr($hexvalue,2,2).substr($hexvalue,0,2))/$divisor;
  }
  elsif ($byte eq "second") {
  	return VCONTROL300_1ByteUParse(substr($hexvalue,2,2),$divisor)
  }
  elsif ($byte eq "first") {
  	return VCONTROL300_1ByteUParse(substr($hexvalue,0,2),$divisor)
  }

  return "";

  #return hex($string)/$divisor;

  #return hex(substr($hexvalue,2,2).substr($hexvalue,0,2))/$divisor;
}
#####################################
sub VCONTROL300_2ByteSParse($$)
#####################################
{
  my $hexvalue = shift;
  my $divisor = shift;

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_2ByteSParse() with hexvalue=$hexvalue";

  return unpack('s', pack('S',hex(substr($hexvalue,2,2).substr($hexvalue,0,2))))/$divisor;
}
#####################################
#sub VCONTROL300_2BytePercentParse($$)
#{
#  my $hexvalue = shift;
#  my $divisor = shift;

#  #return hex(substr($hexvalue,2,2))/$divisor;
#  return hex(substr($hexvalue,0,2))/$divisor;
#}
#####################################
sub VCONTROL300_2ByteHexParse($)
#####################################
{
  my $hexvalue = shift;

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_2ByteHexParse() with hexvalue=$hexvalue";

  #return substr($hexvalue,2,2).substr($hexvalue,0,2);
  return $hexvalue;
}
#####################################
sub VCONTROL300_4ByteParse($$)
#####################################
{
  my $hexvalue = shift;
  my $divisor = shift;

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_4ByteParse() with hexvalue=$hexvalue";

  return hex(substr($hexvalue,6,2).substr($hexvalue,4,2).substr($hexvalue,2,2).substr($hexvalue,0,2))/$divisor;
  #return hex($hexvalue)/$divisor;

}
#####################################
sub VCONTROL300_9ByteParse($$)
#####################################
{
  my $hexvalue = shift;
  my $divisor = shift;

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_9ByteParse() with hexvalue=$hexvalue";

  if ($divisor eq "errorstate") {
	return VCONTROL300_ErrorParse(substr($hexvalue,0,2), substr($hexvalue,2,16));
  }
  return $hexvalue;

}
#####################################
sub VCONTROL300_StateParse($)
#####################################
{
  my $value = hex(shift);

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_StateParse() with key=$value";
  if ($status{$value}) {
	return "$status{$value} ($value)";
  }

  return "";
}
#####################################
sub VCONTROL300_ValveParse($)
#####################################
{
  my $value = hex(shift);

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_ValveParse() with key=$value";
  if ($valve{$value}) {
        return "$valve{$value} ($value)";
  }

  return "No mapping found for value -valve- ($value)";
}
#####################################
sub VCONTROL300_hschemeParse($)
#####################################
{
  my $value = hex(shift);

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_hschemeParse() with key=$value";
  if ($hscheme{$value}) {
        return "$hscheme{$value} ($value)";
  }

  return "No mapping found for value -hscheme- ($value)";
}
#####################################
sub VCONTROL300_ModeParse($)
#####################################
{
  my $hexvalue = shift;

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_ModeParse() with key=$hexvalue";
  if ($modus{$hexvalue}) {
        return "$modus{$hexvalue} ($hexvalue)";
  }

  return "No mapping found for value ($hexvalue)";
}
#####################################
sub VCONTROL300_ErrorParse($$)
#####################################
{
  my $hexvalue = shift;
  my $date = shift;

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_ErrorParse() with key=$hexvalue and date=$date";
#  if ($error_states{$hexvalue}) {
#	if ($hexvalue eq "00") {
#		return "$error_states{$hexvalue} ($hexvalue)";
#	} else {
#        return VCONTROL300_DateParse($date)." $error_states{$hexvalue} ($hexvalue)";
#	}
#  }
  if ($mapping_errorstate_hash{$hexvalue}) {
	if ($hexvalue eq "00") {
		return "$mapping_errorstate_hash{$hexvalue} ($hexvalue)";
	} else {
        return VCONTROL300_DateParse($date)." $mapping_errorstate_hash{$hexvalue} ($hexvalue)";
	}
  }

  return "No mapping found for 'Stoerungscode' value ($hexvalue)";
}
#####################################
sub VCONTROL300_TimerParse($)
#####################################
{
  my $binvalue = shift;

  #Log3 undef, 4, "VCONTROL300: Timer $binvalue";

  $binvalue = pack('H*', "$binvalue");


  #Log3 undef, 2, "VCONTROL300: Timer $binvalue";

  #my ($h1,$h2,$h3,$h4,$h5,$h6,$h7,$h8) = unpack ("CCCCCCCC",$binvalue);
  #my @bytes = ($h1,$h2,$h3,$h4,$h5,$h6,$h7,$h8);
  my @bytes = unpack ("C*",$binvalue);

  my $timer_str;

  #for ( $a = 0; $a < 8; $a = $a+1){
  my $a=0;
  foreach (@bytes) {
	my $byte = $_;

	my $delim = ",";
     #my $delim = "/";
     #if ( $a % 2 ){
     #   $delim = " , ";
     #}

     #my $byte = $bytes[$a];

	 Log3 undef, 4, "VCONTROL300: Timerbyte $byte";

     if ($byte == 0xff){
     	$timer_str = $timer_str."--";
	#if ($a<7) {
		$timer_str = $timer_str."$delim";
	#}
     }
     else{
     	my $hour = ($byte & 0xF8)>>3;
     	my $min = ($byte & 7)*10;

     	$hour = "0$hour" if ( $hour < 10 );
     	$min = "0$min" if ( $min < 10 );

     	$timer_str = $timer_str."$hour:$min$delim";
     }

	 $a++;
  }

  return "$timer_str";

}
#####################################
sub VCONTROL300_DateParse($)
#####################################
{

  my $hexvalue = shift;
  my $vcday;

  Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_DateParse() with Date hexvalue '$hexvalue'";

  #0011223344556677
  #01 23 45 67 89 01 23 45
  #38 03 BF 02 38 03 BF FF
	$vcday = "So" if ( substr($hexvalue,8,2) eq "00" );
  $vcday = "Mo" if ( substr($hexvalue,8,2) eq "01" );
  $vcday = "Di" if ( substr($hexvalue,8,2) eq "02" );
  $vcday = "Mi" if ( substr($hexvalue,8,2) eq "03" );
  $vcday = "Do" if ( substr($hexvalue,8,2) eq "04" );
  $vcday = "Fr" if ( substr($hexvalue,8,2) eq "05" );
  $vcday = "Sa" if ( substr($hexvalue,8,2) eq "06" );
  $vcday = "So" if ( substr($hexvalue,8,2) eq "07" );

	return $vcday.",".substr($hexvalue,6,2).".".substr($hexvalue,4,2).".".substr($hexvalue,0,4)." ".substr($hexvalue,10,2).":".substr($hexvalue,12,2).":".substr($hexvalue,14,2);

}

###########################################################################
###########################################################################
##  CONV ROUTINES
###########################################################################
###########################################################################


#####################################
sub VCONTROL300_1ByteUConv($$)
#####################################
{
  my ($name) = @_;
  my $convvalue = shift;
  my $multiplicator = shift;

  Log3 $name, 5,"VCONTROL300: DEBUGGING VCONTROL300_1ByteUConv() multiplicator = $multiplicator | convvalue=$convvalue";
  if ($multiplicator eq "state"){
	 return VCONTROL300_StateConv($convvalue);
  }
  elsif ($multiplicator eq "mode"){
     return VCONTROL300_ModeConv($convvalue);
  }
  elsif ($multiplicator eq "valve"){
     return VCONTROL300_ValveConv($convvalue);
  }
  elsif ($multiplicator eq "hschemeConv"){
     return VCONTROL300_hschemeConvConv($convvalue);
  }
  elsif ( $multiplicator =~ /^\d+$/) {
	 return (sprintf "%02X", $convvalue*$multiplicator);
	 }
 else {
	return (sprintf "%02X", $convvalue);
}
}
#####################################
sub VCONTROL300_1ByteSConv($$)
#####################################
{
  my ($name) = @_;
  my $convvalue = shift;
  my $multiplicator = shift;
  my $cnvstrvalue;
  Log3 $name, 5,"VCONTROL300: DEBUGGING VCONTROL300_1ByteSConv() multiplicator = $multiplicator | convvalue=$convvalue";
  if ( $multiplicator =~ /^\d+$/) {
    $cnvstrvalue = (sprintf "%02X", $convvalue*$multiplicator);
    }
    else
    {$cnvstrvalue = (sprintf "%02X", $convvalue);}
  if ($convvalue <0){
     return substr($cnvstrvalue,length($cnvstrvalue)-2,2);
  }
  else {
    return $cnvstrvalue;
  }
}
#####################################
sub VCONTROL300_2ByteUConv($$)
#####################################
{
  my $convvalue = shift;
  my $multiplicator = shift;
  my $hexstr;
  if ( $multiplicator =~ /^\d+$/) {
     $hexstr = (sprintf "%04X", $convvalue*$multiplicator);
  }
  else {
     $hexstr = (sprintf "%04X", $convvalue);
  }

  return substr($hexstr,2,2).substr($hexstr,0,2);
}
#####################################
sub VCONTROL300_2ByteSConv($$)
#####################################
{
  my $convvalue = shift;
  my $multiplicator = shift;
  my $cnvstrvalue;

  if ( $multiplicator =~ /^\d+$/) {
     $cnvstrvalue = (sprintf "%04X", $convvalue*$multiplicator);
     }
  else {
     $cnvstrvalue = (sprintf "%04X", $convvalue);
  }
  if ($convvalue <0){
    #return substr($cnvstrvalue,6,2).substr($cnvstrvalue,4,2);
	return substr($cnvstrvalue,14,2).substr($cnvstrvalue,12,2);

  }
  else {
    return substr($cnvstrvalue,2,2).substr($cnvstrvalue,0,2);
  }
}
#####################################
sub VCONTROL300_StateConv($)
#####################################
{
        my $value = shift;

		Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_StateConv() with value=$value";
        return $value if ($value =~ /^\d+$/);

        return sprintf ("%02X",$status{$value});
}
######################################
#sub VCONTROL300_StateConv($){
#        my $value = shift;
#        return $value if ($value =~ /^\d+$/);
#
#        #return (sprintf "%02X",($convvalue eq "on") ? 1 : 0);
#
#        my $count=0;
#        foreach (@state) {
#                my $statecaption = $_;
#                if ($value eq $statecaption) {
#                        #Log3 undef, 5, "VCONTROL300: State '$count'";
#                        return sprintf ("%02X",$count);
#                }
#                $count++;
#        }
#
#        return "";
#}

#####################################
sub VCONTROL300_ModeConv($)
#####################################
{
	my $value = shift;
	return $value if ($value =~ /^\d+$/);

	my $count=0;
	foreach (@mode) {
		my $modecaption = $_;
		if ($value eq $modecaption) {
			#Log3 undef, 5, "VCONTROL300: Mode '$count'";
			return sprintf ("%02X",$count);
		}
		$count++;
	}

	return "";
}
#####################################
sub VCONTROL300_ValveConv($)
#####################################
{
        my $value = shift;

		Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_ValveConv() with value=$value";
        return $value if ($value =~ /^\d+$/);

        return sprintf ("%02X",$status{$value});
}
#####################################
sub VCONTROL300_hschemeConv($)
#####################################
{
        my $value = shift;

		Log3 undef, 5, "VCONTROL300: DEBUGGING VCONTROL300_hschemeConv() with value=$value";
        return $value if ($value =~ /^\d+$/);

        return sprintf ("%02X",$status{$value});
}
####################################
sub VCONTROL300_DateConv($)
#####################################
{
  #Eingabe
  #dd.mm.yyyy_hh:mm:ss
  #Ziel
  #yyyymmddwwhhmmss

  #dd.mm.yyyy
  my $date = shift;
  my $vcday   = substr($date,0,2);
  my $vcmonth = substr($date,3,2);
  my $vcyear  = substr($date,6,4);
  #hh:mm:ss
  my $vchour = substr($date,11,2);
  my $vcmin  = substr($date,14,2);
  my $vcsec  = substr($date,17,2);
  my $wday;
  my $tmp;
  my $hlptime = timelocal($vcsec, $vcmin, $vchour, $vcday, $vcmonth -1 , $vcyear - 1900);
  ($tmp, $tmp, $tmp, $tmp, $tmp, $tmp, $wday) = localtime $hlptime;

  my @Wochentage = ("00","01","02","03","04","05","06");
  $wday = $Wochentage[$wday];

  #0011223344556677
  #01 23 45 67 89 01 23 45
	return $vcyear.$vcmonth.$vcday.$wday.$vchour.$vcmin.$vcsec;

}
#####################################
sub VCONTROL300_TimerConv($$)
#####################################
{

   my ($value,$timer_day) = @_;
   #my $timer_day = shift;
   #my $value = shift;
   my @timerarray = split(",",$value);

   return "" if (@timerarray != 8);

   my @hextimerdata;
   foreach(@timerarray) {
      if ($_ eq "--"){
        push(@hextimerdata,"FF");
      }
     else{
        my ($timerhour, $timermin) = split(":",$_,2);
        if (length($timerhour) != 2 || length($timermin) != 2 ){
           {return "";}
        }

        if ( $timerhour < "00" || $timerhour > "24" ){
           {return "";}
        }

        if ( $timermin ne "00" && $timermin ne "10" && $timermin ne "20" && $timermin ne "30" && $timermin ne "40" && $timermin ne "50"){
           {return "";}
        }

        my $helpvalue = (($timerhour <<3) + ($timermin/10)) & 0xff;
        push(@hextimerdata, (sprintf "%02X", $helpvalue));
     }
   }

   my $suffix="";
   foreach (@hextimerdata){
      $suffix = "$suffix"."$_";
   }

   return $suffix;
}

#####################################
#sub VCONTROL300_RegisterConv($)
#{
#  my $convvalue = shift;
#  if (length($convvalue)==4 || (length($convvalue)==5 && substr($convvalue,2,1)eq"-"))
#    {
#        my $register=substr($convvalue,0,2);
#        my $value=substr($convvalue,2,3);
#        my $hexvalue=sprintf("%02X", $value);
#        if ($value <0)
#        {
#            $hexvalue = substr($hexvalue,length($hexvalue)-2,2);
#        }
#        return $register."01".$hexvalue;
#    }
#  else
#    {
#        return "";
#    }
#}

1;

=pod
=item helper
=item summary    get and set Viessmann parameter
=item summary_DE Lese und Setze Parameter an einer Viessmanheizungf
=begin html


<a name="VCONTROL300"></a>
<h3>VCONTROL300</h3>
<ul>
    VCONTROL300 is a fhem-Modul to control and read information from a VIESSMANN heating via Optolink-adapter.<br><br>

    An Optolink-Adapter is necessary (USB or LAN), you will find information here:<br>
    <a href="https://github.com/openv/openv/wiki">https://github.com/openv/openv/wiki</a><br><br>

    Additionaly you need to know Memory-Adresses for the div. heating types (e.g. V200KW1, VScotHO1, VPlusHO1 ....),<br>
    that will be read by the module to get the measurements or to set the actual state.<br>
    Additional information you will find in the forum <a href="http://forum.fhem.de/index.php/topic,20280.0.html">http://forum.fhem.de/index.php/topic,20280.0.html</a> und auf der wiki Seite <a href="http://www.fhemwiki.de/wiki/Vitotronic_200_%28Viessmann_Heizungssteuerung%29">http://www.fhemwiki.de/wiki/Vitotronic_200_%28Viessmann_Heizungssteuerung%29</a><br><br><br>

    <a name="VCONTROL300define"><b>Define</b></a>
    <ul>
        <code>define &lt;name&gt; VCONTROL &lt;serial-device/LAN-Device:port&gt; &lt;configfile&gt; [&lt;intervall&gt;] </code><br>
        <br>
        <li><b>&lt;serial-device/LAN-Device:port&gt;</b><br>
        USB Port (e.g. com4, /dev/ttyUSB3) or TCPIP:portnumber<br>
        </li>

        <li><b>&lt;configfile&gt;</b><br>
        Path to the configuration file, containing the memory addresses<br>
        </li>

		<li><b>&lt;intervall&gt;</b><br>
        Poll interval in seconds. Default value is 180 seconds.<br>
        </li>

		<li><b>&lt;protocol&gt;</b><br>
        Defines which protocol should be used. Possible values are 300 and KW (Default).<br>
        </li>

		<li><b>&lt;protocolparam&gt;</b><br>
        Defines additional parameters for the protocol.<br/>
		Default value is 0.<br>
        </li>


		<br>
        <b>Example:</b><br><br>

        serial device com4, every 3 minutes will be polled, configuration file name is VCONTROL.cfg, existing in the fhem root directory<br><br>

        Windows:<br>
        define Heizung VCONTROL com4 VCONTROL.cfg 180 kw<br><br>

        Linux:<br>
        define Heizung VCONTROL /dev/ttyUSB3 VCONTROL.cfg 180 kw<br><br>

		Remote via serial2net on target host:<br>
		define Heizung VCONTROL300 &lt;IP&gt;:&lt;Port&gt; 89_VCONTROL300.cfg 180 kw

    </ul>
    <br><br>

    <a name="VCONTROL300set"><b>Set</b></a>
    <ul>
        These commands will be configured in the configuartion file.
    </ul>
    <br><br>
    <a name="VCONTROL300get"><b>Get</b></a>
    <ul>
        get &lt;name&gt; CONFIG<br><br>
        reload the module specific configfile<br><br>

        More commands will be configured in the configuration file.
    </ul>
    <br>
    <a name="VCONTROL300attr"><b>Attributes</b></a>
	<ul><li><code>disable [0|1]</code></li></ul>
	<ul><li><code>updateOnlyChanges [0|1]</code></li></ul>
	<ul><li><code>vitotronicType [200_WO1x|200_KWx|200_HOxx|200_HOE3]</code></li>
	<ul>If not set correctly the internal operation mode mapping is not done correctly! Mode wilbe set to -300-</ul></ul>
	<ul><li><code>setList</code></li></ul>
	<ul><li><code>cumulationSuffixToday &lt; String &gt; default is "_Today"</code></li></ul>
	<ul><li><code>cumulationSuffixTodayStart &lt; String &gt; default is "_TodayStart"</code></li></ul>
	<ul><li><code>cumulationSuffixYesterday &lt; String &gt; default is "_Yesterday"</code></li></ul>
    <br><br>

    <a name="VCONTROL300parameter"><b>configfile</b></a>
    <ul>
       You will find example configuration files for the heating types V200KW1, VScotHO1, VPlusHO1 on the wiki page <a href="http://www.fhemwiki.de/wiki/Vitotronic_200_%28Viessmann_Heizungssteuerung%29">http://www.fhemwiki.de/wiki/Vitotronic_200_%28Viessmann_Heizungssteuerung%29</a>.<br><br>

       The lines of the configuration file can have the following structure:<br><br>

       <li>lines beginning with "#" are comments!<br></li>
       <li>Polling Commands (POLL) to read values.<br></li>
       <li>Set Commandos (SET) to set values.<br></li>
       <li>Mapping Commandos (MAPPING) to map value IDs into readable text.<br></li>
       <br>
       <b>Polling Commands have the following structure:<br><br></b>

       POLL, ADDRESS, ADDRESSTYPE, DIVISOR, READINGNAME, CUMULATION<br><br>

       <ul>
        <li><b>POLL</b><br>
        Indicates that the command is for polling values<br>
        </li>
        <br>
        <li><b>ADDRESS</b><br>
        Memory address of the parameter that should be read out of the heatings memory.<br>
        <br>
        <li><b>ADDRESSTYPE</b><br>
        Indicates the type and length of the databytes to read, respectively.<br>
        Types so far:<br>
        <ul>
          <li>1ByteU        :<br> Read value is 1 Byte without algebraic sign (if column Divisor set to state -> only 0/1 or off/on)<br></li>
          <li>1ByteS        :<br> Read value is 1 Byte with algebraic sign (if column Divisor set to state -> only 0/1 or off/on)<br></li>
          <li>2ByteU        :<br> Read value is 2 Byte without algebraic sign<br></li>
		  <li>2ByteS        :<br> Read value is 2 Byte with algebraic sign<br></li>
          <!--<li>2BytePercent  :<br> Read value is 2 Byte in percent<br></li>-->
          <li>4Byte         :<br> Read value is 4 Byte<br></li>
          <li>mode          :<br> Read value is the actual operating status<br></li>
          <li>timer         :<br> Read value is an 8 Byte timer value<br></li>
          <li>date          :<br> Read value is an 8 Byte timestamp<br></li>
          POLL Commands unsing the method timer will not be polled permanent, they have to be read by a GET Commando explicitly.<br>
          GET &lt;devicename&gt; TIMER<br>
        </ul>
        </li>
        <br>
        <li><b>DIVISOR</b><br>
        1/10/10/.. If the parsed value is multiplied by a factor, you can configure a divisor.<br>
        state      Additionally for values, that just deliver 0 or 1, you can configure state in this column.<br>
                   This will force the reading to report off and on, instead of 0 and 1.<br>
        valve      Additionally for values "Valve (Bauart des Umschaltventils)" that just deliver 0,1,2 or 3, you can configure valve in this column.<br>
                   This will force the reading to report 0:ohne, 1:Viessmann_Ventil, 2:Wilo_Ventil, 3:Grundfos_Ventil.
        hscheme    shows heating circuit hot water scheme (Heizkreiswarmwasserschema)<br>
        </li>
        <br>
        <li><b>READINGNAME</b><br>
        The read and parsed value will be stored in a reading with this name.
        </li>
        <br>
        <li><b>CUMULATION</b><br>
        Accumulated day values will be automatically stored for polling commands with the value day in the column CUMULATION.<br>
        Futhermore  the values of the last day will be stored in additional readings after 00:00.<br>
        So you have the opportunity to plot daily values.<br>
        The reading names will be supplemented by DayStart, Today and LastDay!<br>
        </li>

       <br>
       Examples:<br><br>
       <code>POLL,	0804,	2ByteS,	10,	Temp-WarmWater-Actual,	-<br></code>
       <code>POLL,	088A,	2ByteU,  1, BurnerStarts,			day<br></code>
        </ul>

       <br><br>
       <b>Set Commands have the following structure:<br><br></b>

       SET, ADDRESS, ADDRESSTYPE, MULTIPLICATOR, SETNAME, NEXTSET or DAY<br><br>

       <ul>
        <li><b>SET</b><br>
        Indicates that the command is for setting values<br>
        </li>
        <br>

        <li><b>ADDRESS</b><br>
			Memory Address where the value has to be written in the memory of the heating.<br>
			<br>
			There are two Address versions:<br>
			<li>Version 1: Value to be set is fix, e.g. Spar Mode on is fix 01<br>
			</li>
			<li>Version 2: Value has to be passed, e.g. warm water temperature<br></li>
        </li>
        <br>

        <li><b>ADDRESSTYPE</b><br>
        The type of the address, i.e. how many databytes the to set address will expect.<br>
        <ul>
          <li>1ByteU        :<br> Value to be written in 1 Byte without algebraic sign<br>with Version 2 it has to be a number<br></li>
		  <li>1ByteUx10     :<br> Same as 1ByteU, however the to be sent value is multiplied with a factor 10<br></li>
          <li>1ByteS        :<br> Value to be written in 1 Byte with algebraic sign<br>with Version 2 it has to be a number<br></li>
          <li>1ByteSx10     :<br> Same as 1ByteS, however the to be sent value is multiplied with a factor 10<br></li>
		  <li>2ByteU        :<br> Value to be written in 2 Byte without algebraic sign<br>with Version 2 it has to be a number<br></li>
		  <li>1ByteUx10     :<br> Same as 1ByteU, however the to be sent value is multiplied with a factor 10<br></li>
		  <li>2ByteS        :<br> Value to be written in 2 Byte with algebraic sign<br>with Version 2 it has to be a number<br></li>
          <li>2ByteSx10     :<br> Same as 2ByteS, however the to be sent value is multiplied with a factor 10<br></li>
		  <li>timer         :<br> Value to be written in an 8 Byte timer value<br>with Version 2 it has to be a string with this structure:<br>
                                  8 times of day comma separeted.  (ON1,OFF1,ON2,OFF2,ON3,OFF3,ON4,OFF4)<br>
                                  no time needed ha to be specified with -- .<br>
                                  Minutes of the times are just allowed to thi values: 00,10,20,30,40 or 50<br>
                                  Example: 06:10,12:00,16:00,23:00,--,--,--,--</li>
          <li>date          :<br> Value to be written is an 8 Byte timestamp<br>with Version 2 it has to be a string with this structure:<br>
                                  format specified is DD.MM.YYYY_HH:MM:SS<br>
                                  Example: 21.03.2014_21:35:00</li>
        </ul>
        </li>
        <br>

		<li><b>SETNAME</b><br>
			SETNAME is the command that will be used in FHEM to set a value of a device<br>
			set &lt;devicename&gt; &lt;setcmd&gt;<br>
			e.g. SET &lt;devicename&gt; WW to set the actual operational status to Warm Water processing<br>
        </li>
        <br>

        <li><b>NEXTSET or DAY</b><br>
        This column has two functions:
        <ul>
        <li> If this column is set to a name of another SETNAME, this SETNAME will be processed directly afterwards.<br>
            Example: after setting 'Spar Mode on (S-ON)', you have to set 'Party Mode off (P-OFF)'<br>
		</li>
        <li>Using timer as ADDRESSTYPE, so a week day has to be specified in this column.<br>
            possible values: MO DI MI DO FR SA SO<br></li>
        </li>
        <br>
        </ul>
        Examples:<br><br>
        <code>SET,	230101, 1ByteU,	state,	WarmwasserEinmalig,		-<br></code>
        <code>SET,  230201, 1ByteU,	state,	SparmodusEin,			PartymodusAus<br></code>
        <code>SET,	6300, 	1ByteU,	1,		WarmwasserTemperatur,	-<br></code>
        <code>SET, 	2000, 	timer,	1,		Timer_Warmwasser_MO,	MO<br></code>
        </ul>
       <br>
       <b>Mapping Commands have the following structure:<br><br></b>

       MAPPING, MAPPINGTABLE, KEY, TEXTVALUE (without comma inside!), -, -<br><br>

       <ul>
        <li><b>MAPPING</b><br>
        Indicates that a key value pair mapping is given. Mainly for translating an error code ID into readable text.<br>
        </li>
        <br>
        <li><b>MAPPINGTABLE</b><br>
        MAPPINGTABLE = ERRORSTATE indicates that error state mapping hash table is filled.<br>
		MAPPINGTABLE = OPERATIONSTATE indicates optional mapping for operation modes. If not given the internal mappings are used according to attribute vitotronicType<br>
        <br>
        <li><b>KEY</b><br>
        If MAPPINGTABLE = ERRORSTATE, then KEY is error code ID as shown in front panel error history.<br>
        If MAPPINGTABLE = OPERATIONSTATE, then KEY is operation mode ID.<br>
        </li>
        <br>
        <li><b>TEXTVALUE</b><br>
        If MAPPINGTABLE = ERRORSTATE, then error description shown in Viessmann service manual according to given error code.<br>
        If MAPPINGTABLE = OPERATIONSTATE, then this description is used as operation mode and not according to attribute vitotronicType selection<br>
        </li>
       <br>
       Examples:<br><br>
       <code>MAPPING, ERRORSTATE, 00, Regelbetrieb (kein Fehlereintrag vorhanden), - , -</code><br>
       <code>MAPPING, ERRORSTATE, 0F, Wartung (fuer Reset Codieradresse 24 auf 0 stellen), - , -</code><br>
       <code>MAPPING, ERRORSTATE, E6, Anlagendruck zu gering (Wasser nachfuellen), - , -</code><br>
       <code>MAPPING, ERRORSTATE, EE, Kein Flammensignal(Gasversorgung pruefen), - , -</code><br>
	   <br>
       <code>MAPPING, OPERATIONSTATE, 00, Abschaltbetrieb (weder Heizung noch Warmwasser), - , -</code><br>
       <code>MAPPING, OPERATIONSTATE, 01, Nur Warmwasser ist an, - , -</code><br>
       <code>MAPPING, OPERATIONSTATE, 02, Heizen und Warmwasser eingeschaltet, - , -</code><br>
       </ul>
       <br>
    </ul>
    <br>
    <a name="VCONTROL300readings"><b>Readings</b></a>
    <ul>The values read will be stored in readings, that will be configured as described above.</ul>
</ul>

=end html

=begin html_DE

<a name="VCONTROL300"></a>
<h3>VCONTROL300</h3>
<ul>

Please read englisch description



Beispiel einer sehr 89_VCONTROL300.cfg:
(Nutzung in einem Vitovalor 300P)


###############################################################################
#	POLL,SENDCMD   , PARSE, DIVISOR, READING-NAME        , KUMULATION
###############################################################################


###############################################################################
#     TESTBEREICH   TEST Beginnen immer mit Unterstrich "_"
###############################################################################
#   TEST Geraeteeinstellungen
POLL, 0883, 1ByteU, state, _Brennerstoerung, -
POLL, 7507, 1ByteU, state, _Fehler1, -
POLL, 7510,1ByteU, state, _Fehler2, -
POLL, 0AA0, 1ByteU, mode, _AM1_Output_1, -
POLL, 0AA1, 1ByteU, mode, _AM1_Output_2, -
POLL, 0A93, 2ByteU, 1, _EA1_Wert_Extern_0__10V, -
#   TEST Brenner
POLL, 55DE, 1ByteU, state, _BrennerT , -
###############################################################################
#     TESTBEREICH   TEST  ENDE
###############################################################################


###############################################################################
#	PUMPEN
###############################################################################

POLL, 0A3C, 2ByteU, 1, Pumpendrehzahl   , -
POLL, 6762, 2ByteU, 1, Pumpennachlauf   , -
POLL, 6765, 1ByteU, valve , Pumpen-BauartUmschaltventil   , -
#  Erläuterung =     0:ohne, 1:Viessmann_Ventil, 2:Wilo_Ventil, 3:Grundfos_Ventil
POLL, 7663, 2ByteU_1stByte, state, Pumpenstatus	,-
POLL, 7660, 2ByteU_1stByte, state, Pumpenstatus-intern	,-
POLL, 7663, 2ByteU_2ndByte, 1, Pumpendrehzahl	,-
POLL, 7660, 2ByteU_2ndByte, 1, Pumpendrehzahl-intern	,-
POLL, 6513, 1ByteU, state, Pumpen-Speicherladepumpe	,-

###############################################################################
#     TEMPERATUREN
###############################################################################
POLL, 0810, 2ByteU, 10, BR-Temp-Vorlauf	, -
POLL, 0804, 2ByteU, 10, BR-Temp-Warmwasser ,-  #was ist der Unterschied zu 080C?
POLL, 6300, 1ByteU, 1, BR-Temp-Warmwasser-Soll	, -
POLL, 0812, 2ByteU, 10, BR-Temp-Speicher-Ladesensor          , - #identisch zur Wassertemperatur, angeblich ''Speicher Ladesensor''
POLL, 080A, 2ByteU, 1, _BR-Temp-Ruecklauf   , -
POLL, 555A, 2ByteU, 10, BR-Temp-Kessel-Soll, -
POLL, 2900, 2ByteS, 10, BR-Temp-Vorlauf-1 , -
POLL, 081A, 2ByteU, 10, BR-Temp-Vorlauf-2 , -
POLL, A391, 1ByteU, 100, BR-Temp-Kessel-Soll-Active , -
POLL, A393, 1ByteU, 100, BR-Temp-Kessel-Vorlauf-Aktuell , -
POLL, A3C5, 2ByteU, 100, BR-Temp-Warmwasser-Soll-DHWC , -

###############################################################################
#     EINSTELLUNGEN HK1 ohne Mischerregelegung
###############################################################################
#	Einstellungen HK1
POLL, 27D3, 1ByteU, 10, HK1-Kennlinie-Neigung ,-
POLL, 27D4, 1ByteU, 1, HK1-Kennlinie-Niveau ,-
POLL, 2309, date, 1 , _HK1-Urlaub-Beginn , -
POLL, 2311, date, 1 , _HK1-Urlaub-Ende   , -
#	Temperaturen HK1
POLL, 2544, 2ByteU, 10, HK1-Temp-Vorlauf-Soll, -
POLL, 2306, 1ByteU, 1, HK1-Temp-Raum-Soll-3-37 , -
POLL, 2307, 1ByteU, 1, HK1-Temp-Raum-Soll-Reduz-3-37 , -
POLL, 27A3, 1ByteU, 1, HK1-Temp-Frostgrenze ,-
#       Timer  HK1
POLL, 2000, timer, 1, _HK1_Timer_HK1_1MO, -
POLL, 2008, timer, 1, _HK1_Timer_HK1_2DI, -
POLL, 2010, timer, 1, _HK1_Timer_HK1_3MI, -
POLL, 2018, timer, 1, _HK1_Timer_HK1_4DO, -
POLL, 2020, timer, 1, _HK1_Timer_HK1_5FR, -
POLL, 2028, timer, 1, _HK1_Timer_HK1_6SA, -
POLL, 2030, timer, 1, _HK1_Timer_HK1_7SO, -
#       WWTimer  HK1
POLL, 2100, timer, 1, _HK1_Timer_HK1_Wasser_1MO,-
POLL, 2108, timer, 1, _HK1_Timer_HK1_Wasser_2DI,-
POLL, 2110, timer, 1, _HK1_Timer_HK1_Wasser_3MI,-
POLL, 2118, timer, 1, _HK1_Timer_HK1_Wasser_4DO,-
POLL, 2120, timer, 1, _HK1_Timer_HK1_Wasser_5FR,-
POLL, 2128, timer, 1, _HK1_Timer_HK1_Wasser_6SA,-
POLL, 2130, timer, 1, _HK1_Timer_HK1_Wasser_7SO,-
#       Betriebsart HK1
POLL, 2323, 1ByteU, mode, HK1-Betriebsart ,-  #0:Abschaltbetrieb, 1:Nur_Warmwasser, 2:Heizen_und_Warmwasser, 3:reduz, 4:voll
POLL, 2302, 1ByteU, state, HK1-Betriebsart-Spar, -
POLL, 2303, 1ByteU, state, HK1-Betriebsart-Party, -
POLL, 2330, 1ByteU, state, HK1-Betriebsart-Status  , -
POLL, 2331, 1ByteU, state, HK1-Betriebsart-Status-Reduziert  , -

###############################################################################
#     EINSTELLUNGEN HK1 mit Mischerregelung = Heizkörper
###############################################################################
#	Einstellungen HK2
POLL, 37D3, 1ByteU, 10, HK2-Kennlinie-Neigung ,-
POLL, 37D4, 1ByteU, 1, HK2-Kennlinie-Niveau ,-
POLL, 3309, date, 1 , _HK2-Urlaubs-Beginn , -
POLL, 3311, date, 1 , _HK2-Urlaubs-Ende   , -
#	Temperaturen HK2
POLL, 3544, 2ByteU, 10, HK2-Temp-Soll-Vorlauf, -
POLL, 3306, 1ByteU, 1, HK2-Temp-Soll-Raum-3-37      , -
POLL, 3307, 1ByteU, 1, HK2-Temp-Soll-Reduz-3-37  , -
POLL, 37A3, 1ByteU, 1, HK2-Temp-Frostgrenze ,-
#       Timer  HK2
POLL, 3000, timer, 1, _HK2_Timer_1MO, -
POLL, 3008, timer, 1, _HK2_Timer_2DI, -
POLL, 3010, timer, 1, _HK2_Timer_3MI, -
POLL, 3018, timer, 1, _HK2_Timer_4DO, -
POLL, 3020, timer, 1, _HK2_Timer_5FR, -
POLL, 3028, timer, 1, _HK2_Timer_6SA, -
POLL, 3030, timer, 1, _HK2_Timer_7SO, -
#       WWTimer  HK2
POLL, 3100, timer, 1, _HK2_Timer_Wasser_1MO,-
POLL, 3108, timer, 1, _HK2_Timer_Wasser_2DI,-
POLL, 3110, timer, 1, _HK2_Timer_Wasser_3MI,-
POLL, 3118, timer, 1, _HK2_Timer_Wasser_4DO,-
POLL, 3120, timer, 1, _HK2_Timer_Wasser_5FR,-
POLL, 3128, timer, 1, _HK2_Timer_Wasser_6SA,-
POLL, 3130, timer, 1, _HK2_Timer_Wasser_7SO,-
#       Betriebsarten HK2
POLL, 3323, 1ByteU, mode, HK2-Betriebsart ,-  #0:Abschaltbetrieb, 1:Nur_Warmwasser, 2:Heizen_und_Warmwasser, 3:reduz, 4:voll
POLL, 3302, 1ByteU, state, HK2-Betriebsart-Spar, -
POLL, 3303, 1ByteU, state, HK2-Betriebsart-Party, -
POLL, 3330, 1ByteU, state, HK2-Betriebsart-Status  , -
POLL, 3331, 1ByteU, state, HK2-Betriebsart-Status-Reduziert  , -


###############################################################################
#     EINSTELLUNGEN HK3 mit Mischerregelung = Fußbodenheizung
###############################################################################
#	Einstellungen HK3
POLL, 47D3, 1ByteU, 10, HK3-Kennlinie-Neigung ,-
POLL, 47D4, 1ByteU, 1, HK3-Kennlinie-Niveau ,-
POLL, 4309, date, 1 , _HK3-Urlaubs-Beginn , -
POLL, 4311, date, 1 , _HK3-Urlaubs-Ende   , -
#	Temperaturen HK3
POLL, 4544, 2ByteU, 10, HK3-Temp-Vorlauf-Soll, -
POLL, 4306, 1ByteU, 1, HK3-Temp-Raum-Soll-3-37   , -
POLL, 4307, 1ByteU, 1, HK3-Temp-Raum-Soll-Reduziert-3-37  , -
POLL, 47A3, 1ByteU, 1, HK3-Temp-Frostgrenze ,-
#       Timer  HK3
POLL, 4000, timer, 1, _HK3_Timer_1MO, -
POLL, 4008, timer, 1, _HK3_Timer_2DI, -
POLL, 4010, timer, 1, _HK3_Timer_3MI, -
POLL, 4018, timer, 1, _HK3_Timer_4DO, -
POLL, 4020, timer, 1, _HK3_Timer_5FR, -
POLL, 4028, timer, 1, _HK3_Timer_6SA, -
POLL, 4030, timer, 1, _HK3_Timer_7SO, -
#       WWTimer  HK3
POLL, 4100, timer, 1, _HK3_Timer_Wasser_1MO,-
POLL, 4108, timer, 1, _HK3_Timer_Wasser_2DI,-
POLL, 4110, timer, 1, _HK3_Timer_Wasser_3MI,-
POLL, 4118, timer, 1, _HK3_Timer_Wasser_4DO,-
POLL, 4120, timer, 1, _HK3_Timer_Wasser_5FR,-
POLL, 4128, timer, 1, _HK3_Timer_Wasser_6SA,-
POLL, 4130, timer, 1, _HK3_Timer_Wasser_7SO,-
#       Betriebsarten HK3
POLL, 4323, 1ByteU, mode, HK3-Betriebsart ,-  #0:Abschaltbetrieb, 1:Nur_Warmwasser, 2:Heizen_und_Warmwasser, 3:reduz, 4:voll
POLL, 4302, 1ByteU, state, HK3-Betriebsart-Spar, -
POLL, 4303, 1ByteU, state, HK3-Betriebsart-Party, -
POLL, 4330, 1ByteU, state, HK3-Betriebsart-Status  , -
POLL, 4331, 1ByteU, state, HK3-Betriebsart-Status-Reduziert  , -


###############################################################################
# Systemdaten   (allgemein)
##############################################################################
POLL, 088E, date, 1, AA-System-Zeit, -
POLL, 7700, 1ByteU, hscheme, AA-System-Heizkreiswarmwasserschema, -
#     1=A1 2=A1+WW 3=M2 4=M2+WW 5=A1+M1 6=A1+M2+WW 7=M2+M3 8=M2+M3+WW 9=A1+M2+M3 10=A1+M2+M3+WW

POLL, 7701, 1ByteU, 1, AA-Anlagentyp, -
#     1=Einkessel
#     2=Mehrkessel-LON-Kaskadenbetrieb
#     3=Mehrkessel-Kontaktsteuerung-Kaskaderegelegung über Schaltkontakte eingebunden (Kaskade anderer Hersteller)

POLL, 7751, 1ByteU, 1, AA-Hydr.-Weiche-Int.-Pumpe, -
# 0=läuft bei Anforderung
# 1=läuft bei Anforderung, aber nur wenn Brenner läuft
# 2=Pufferspeicher: Interne Pumpe läuft bei Anforderung nur, wenn der Brenner läuft.

POLL, 7777, 1ByteU, 1, AA-Viesmann-Teilnehmernummer-LON, -
# 1 = Kesselregelung 10 = Heizkreisregelung   5 = Kaskade

POLL, 7798, 1ByteU, 1, AA-Viesmann-Anlagennummer, -   # Anlagennummer innerhalb einer Viessmanndomain
POLL, 00F8, 2ByteH, 1, AA-System-ID, -   # Gerätekennung der Anlage z.B. 20E3 (Vitovalor300P)


##############################################################################
# Brennerdaten
##############################################################################
#       allgemeine Temperaturen
POLL, 0808, 2ByteU, 10, BR-Temp-Abgas, -
POLL, 5525, 2ByteS, 10, BR-Temp-Aussen-Tiefpass_30, - # 5525 liefert "Tiefpass-Temperatur", 5527 liefert "gedaempft" ueber 30 Minuten
POLL, 5527, 2ByteS, 10, BR-Temp-Aussen-Gedaempft_30, - # 5525 liefert "Tiefpass-Temperatur", 5527 liefert "gedaempft" ueber 30 Minuten
POLL, 6760, 1ByteU, 1, BR-Temp-Kesseloffset  , -
POLL, 0800, 2ByteS, 10, BR-Temp-Aussen, -
POLL, 0804, 2ByteS, 10, BR-Temp-WarmWasser-Ist[°C], -
POLL, 6300, 1ByteU, 1, BR-Temp-WarmWasser-Soll[°C], -
POLL, 0802, 2ByteS, 10, BR-Temp-Kessel-Ist[°C], -
POLL, 080E, 2ByteS, 10, BR-Temp-Aussen-HK3-Ist[°C], -
POLL, 0842, 1ByteU, state, BR-Brenner, -
POLL, 088A, 2ByteU, 1, BR-BrennerStarts, day
POLL, 7574, 4Byte , 1, BR-Gasverbrauch, -
POLL, 6515, 1ByteU, state, BR-Warmwasser-Zirkulationspumpe2 ,-  # gleich wie ....0846 ??
POLL, 0846, 1ByteU, state, BR-Warmwasser-Zirkulationspumpe , - # gleich wie ...6615 ??
POLL, 55D3, 1ByteU, state, BR-Brennerstatus, -
POLL, 08AB, 4Byte , 3600, BR-BrennerStundenbisWartung, -
POLL, 08A7, 4Byte, 3600, BR-Betriebsstunden , day
POLL, 2306, 1ByteU, 1, BR-Temp-Raum-Soll-HK1[°C], -
POLL, 3306, 1ByteU, 1, BR-Temp-Raum-Soll-HK2[°C], -
POLL, 4306, 1ByteU, 1, BR-Temp-Raum-Soll-HK3[°C], -
POLL, 5726, 2ByteU, 10, BR-Gasverbrauch-Codierung, -
#POLL, 2305, 1ByteU, 10, BR-Neigung-HK3, -
#POLL, 2304, 1ByteU, 1, BR-Niveau-HK3, -

##############################################################################
# BEGINN speziell Vitovalor300P
##############################################################################
POLL, 0952, 2ByteS, 10  , FCU-Temp-Aussen-Celsius[°C], -
        # (Wert i.O. geprüft)
POLL, D7B4, 4Byte , 1   , FCU-Betriebsstunden, day
        # (Wert i.O. geprüft)
POLL, 0B17, 2ByteU, 10  , FCU-Temp-Pufferspeicher-oben[°C], -
        # (Wert i.O. geprüft)
POLL, 0B19, 2ByteU, 10  , FCU-Temp-Pufferspeicher-unten[°C], -
        # (Wert i.O. geprüft)
POLL, CE21, 1ByteU, 1   , FCU-Strom-Eigenerzeugung[%], -
        #  soll so sein / Wert nicht ermittelbar bei mir
POLL, A38F, 1ByteU, 2   , FCU-Strom-Erzeugung-rel[%], -
        #  war auch Brennerleistung ??? format 1 ??? n.i.O (????keine Ahnung?????)
POLL, CE1F, 1ByteU, 1   , FCU-Strom-Eigennutzung[%], -
        # (Wert i.O. geprüft -> 255 = keine Stromerzeugung !!!)

##############################################################################
# ENDE Speziell Vitovalor300P
##############################################################################



</ul>
=end html_DE
=cut
