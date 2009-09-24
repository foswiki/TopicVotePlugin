# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009 Sven Hess, shess@seibert-media.net
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html


package Foswiki::Plugins::TopicVotePlugin;

use strict;
require Foswiki::Func;    # The plugins API
require Foswiki::Plugins; # For the API version

use vars qw(%pollUser %pollLog %config);

our $VERSION = '$Rev: 3048 (2009-03-12) $';
our $RELEASE = 'v1.2';
our $SHORTDESCRIPTION = 'Enables voting on topics';
our $NO_PREFS_IN_TOPIC = 1;



sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
                                     __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    # get name of current wiki user
    $config{USER} = Foswiki::Func::getWikiName($user);
    
    # register handler for enabling votings
    Foswiki::Func::registerTagHandler( 'TOPICVOTE', \&_topicvote );
        
    # register handler for creating a vote configuration
    Foswiki::Func::registerTagHandler( 'TOPICVOTESETUP', \&_topicvotesetup );

    # register REST handler for saving votes
    Foswiki::Func::registerRESTHandler('savevote', \&_restSaveVote);

    # Plugin correctly initialized
    return 1;
}

# creates necessary configuration tables:
# - saves setup to current topic
# - saves log to current topic +Log 
sub _topicvotesetup {
  my ( $session, $params, $topic, $webName ) = @_;
  
  $config{TOPICLOG} = $topic."Log";
  
  my( $meta, $topicdata ) = Foswiki::Func::readTopic( $webName, $topic );
  
  my $plugin_conf_table = "*Voting setup*";
  $plugin_conf_table .= "\n<!-- DO NOT CHANGE TABLE ORDER -->";
  $plugin_conf_table .= "\n| *username* | *credit points* | *latest vote* | *comment* |\n";
  $plugin_conf_table .= "| Main.ExampleUser | 20 | - | please edit me |\n\n";
  $plugin_conf_table .= "Log: ".$config{TOPICLOG};
  
  $topicdata =~ s/%TOPICVOTESETUP%\s*/$plugin_conf_table/mg;
  
  Foswiki::Func::saveTopic( $webName, $topic, $meta, $topicdata);
  
  my( $logMeta, $logTopicdata ) = Foswiki::Func::readTopic( $webName, $config{TOPICLOG} );
  
  my $plugin_log_table = "\n\n*Voting log*";
  $plugin_log_table .= "\n<!-- DO NOT EDIT THIS TABLE -->";
  $plugin_log_table .= "\n| *date* | *username* | *topic* | *credit points* |\n\n";
  $plugin_log_table .= "Setup: ".$topic;
    
  $logTopicdata .= $plugin_log_table;
  
  Foswiki::Func::saveTopic( $webName, $config{TOPICLOG}, $logMeta, $logTopicdata);
  _redirect($webName, $topic);
  
  return '';
}

# inserts voting form and voting stats
sub _topicvote {
  my ( $session, $params, $topic, $webName ) = @_;
  
  my $config_topic = $params->{topic} || $params->{"_DEFAULT"} || $topic;
  my $disable = $params->{disable};
  my $max_points = $params->{maxpoints} || 0;
  my $format = $params->{'format'} || '$board$form';
      
  if($config_topic =~ m/\./g) {
    ( $config{CONFWEB}, $config{CONFTOPIC} ) =
      $Foswiki::Plugins::SESSION->normalizeWebTopicName( '', $config_topic );
  }
  else {
    ( $config{CONFWEB}, $config{CONFTOPIC} ) =
      $Foswiki::Plugins::SESSION->normalizeWebTopicName( $webName, $config_topic );
  }  
  
  $config{TOPICLOG} =
      $Foswiki::Plugins::SESSION->normalizeWebTopicName( $config{CONFWEB}, $config{CONFTOPIC}."Log" );
  
  # creates hash of all voters
  _createVoterList();
  
  # creates hash of all saved votes
  _createPollLog();
       
  # checks if vote configuration found
  if(scalar keys %pollUser < 1) {
    
    my $mes = "No configuration found.";
    return _error($mes);
  }
       
  my $sum_points = 0;
  my $user_votes = 0;
  
  # Sum up all votes from user and topic
  while (my $user = each(%pollLog)) {
    
    while ((my $date, my $points) = each(%{$pollLog{$user}{$webName.".".$topic}})) {
    
      $sum_points += $points;
      $user_votes += $points if($user eq $config{USER});
    }
  }
  
  # add topic score to meta data of topic
  _addMetaInfo($webName, $topic, $sum_points);
  
  
 
  # creates voting stats
  my $voting_stats = "\n| *topic score: $sum_points* || \n";
  
  # checks voting permission of current user
#   if(!exists $pollUser{$config{USER}}) {
#         
#   }

  
  
  my $stats_suffix = "";
  
  my $points_left = $pollUser{$config{USER}}{points} || 0; 
  
  $stats_suffix = "(of $max_points)" if($max_points > 0);
  
  $voting_stats .= "| credit points shared: | $user_votes $stats_suffix |\n";
  $voting_stats .= "";
  $voting_stats .= "| credit points left: | $points_left |\n";
  
  my $voting_form = '';
  my $disable_form = ' readonly="readonly"';
  my $disable_button = ' disabled="true"';
  
   
  if(($pollUser{$config{USER}}{points} > 0) && 
      (($max_points < 1) || ($user_votes < $max_points)) && 
      ($disable ne 1)) {
   
    $disable_form = '';
    $disable_button = '';
  }
  
  # creates voting form
  $voting_form = "\n| <form action=\"%SCRIPTURLPATH{\"rest/TopicVotePlugin/savevote\"}%\" method=\"post\"><input type=\"text\" size=\"3\" id=\"credits\" name=\"credits\"$disable_form />";
  $voting_form .= " <input type=\"submit\" value=\"vote!\" class=\"foswikiButton\"$disable_button />";
  $voting_form .= " <input type=\"hidden\" value=\"".$webName.".".$topic."\" name=\"voted_t\" />";
  $voting_form .= " <input type=\"hidden\" value=\"".$config{CONFWEB}.".".$config{CONFTOPIC}."\" name=\"conf_t\" />";
  $voting_form .= " <input type=\"hidden\" value=\"".$max_points."\" name=\"max_p\" />";
  $voting_form .= "</form> |\n";

  $format =~ s/\$score/$sum_points/g;
  $format =~ s/\$board/$voting_stats/g;
  $format =~ s/\$form/$voting_form/g;
  
  return $format;
}


sub _addMetaInfo {
  my ($web, $topic, $score) = @_;

  # get topic text and meta data of current topic
  my ( $meta, $topicdata ) = Foswiki::Func::readTopic($web, $topic);
    
  
  # add meta data  
  $meta->putKeyed( 'FIELD', { name => $config{CONFTOPIC}."Score", 
                              title => 'Topic score',
                              value =>$score } );

  Foswiki::Func::saveTopic( $web, $topic, $meta, $topicdata, 
                          { dontlog => 1, minor => 1 } );

  $meta->finish();
}


sub _createVoterList {

  # get topic text of configuration topic
  my $topicdata = Foswiki::Func::readTopic($config{CONFWEB}, $config{CONFTOPIC});
    
  my $wikiword_p = $Foswiki::regex{wikiWordRegex};
  my $webname_p = $Foswiki::regex{webNameRegex};
  
  # extract user configuration for voting and create hash of it
  $topicdata =~ s/^\|\s*($webname_p\.)?($wikiword_p)\s*\|\s*(\d+)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|.*$/_userlistmap($2,$3,$4,$5)/mego;
  
  return 1;
}

sub _createPollLog {
  
  # get topic text of configuration topic
  my $topicdata = Foswiki::Func::readTopic($config{CONFWEB}, $config{TOPICLOG});
 
  my $wikiword_p = $Foswiki::regex{wikiWordRegex};
  my $webname_p = $Foswiki::regex{webNameRegex};
  
  # extract all votes and create hash of it
  $topicdata =~ s/^\|\s*(.*?)\s*\|\s*($webname_p\.)?($wikiword_p)\s*\|\s*($webname_p\..*?)\s*\|\s*(\d+)\s*\|.*$/_logmap($1,$3,$4,$5)/mego;
  
  
  return 1;
}

# creates hash of all votes
sub _logmap {
  my( $date, $user, $topic, $points ) = @_;
   
  $pollLog{$user}{$topic}{$date} = 0;
  $pollLog{$user}{$topic}{$date} += $points || 0;
  
  return '';
}

# creates hash of all permitted users
sub _userlistmap {
    my( $user, $points, $date, $comment ) = @_;
    
    $pollUser{$user}{points} = $points || 0;
    $pollUser{$user}{date} = $date || '';
    $pollUser{$user}{comment} = $comment || '';
    
    return '';
}

# inserts new vote to credit log
sub _updatePollLog {
  my $submitted_credits = $_[0];
  my $voted_topic = $_[1];
  my $today = $_[2];
  my $log;
  my $theader;
  
    
  my( $meta, $topicdata ) = Foswiki::Func::readTopic($config{CONFWEB}, $config{TOPICLOG});
  
  
  if($topicdata 
      =~ m/^(\s*\|\s*\*date\*\s*\|\s*\*username\*\s*\|\s*\*topic\*\s*\|\s*\*credit points\*\s*\|)\s*$/mgo) {
    
    $theader = $1;
    $log = $theader."\n| $today | $config{USER} | $voted_topic | $submitted_credits |";
  }
  
  $theader = quotemeta($theader);
  
  if($topicdata =~ s/^$theader/$log/mgo) {
    Foswiki::Func::saveTopic( $config{CONFWEB}, $config{TOPICLOG}, $meta, $topicdata );
  }
  
  return 1; 
}

# sets remaining credit points of user
# sets date of recent changes
#
# return 1 - if setting succed
sub _updatePollConfig {
  my $submitted_credits = $_[0];
  my $today = $_[1];
  my $confentry;
      
  my( $meta, $topicdata ) = Foswiki::Func::readTopic($config{CONFWEB}, $config{CONFTOPIC});
  my $webname_p = $Foswiki::regex{webNameRegex};
    
  if($topicdata =~ m/^(\|\s*($webname_p\.)?$config{USER}\s*\|\s*\d+\s*\|\s*.*?\s*\|\s*.*?\s*\|)\s*$/mgo) {
      
    $confentry = $1;
    
    if($confentry =~ m/^\|\s*($webname_p\.)?$config{USER}\s*\|\s*(\d+)\s*\|\s*.*?\s*\|\s*(.*?)\s*\|$/mgo) {
      my $credits = $2;
      my $comment = $3;
      my $new_credits = $credits - $submitted_credits;
      
      if($new_credits < 0) {
        
        return 0;
      }
      
      $config{USER} = Foswiki::Func::getWikiUserName($config{USER});
      
      $confentry = quotemeta($confentry);
      my $editentry = "| $config{USER} | $new_credits | $today | $comment |";
      
      if($topicdata =~ s/$confentry/$editentry/mgo) {
        Foswiki::Func::saveTopic( $config{CONFWEB}, $config{CONFTOPIC}, $meta, $topicdata );
        return 1;
      }
    }
  }
  
  return 0;
}

# handles rest call 'savevote'
# - saves submitted credits
# - updates credits of voting user
# - redirects to current topic
sub _restSaveVote {
  my ($session) = @_;
      
  my $query = Foswiki::Func::getCgiQuery();
  return unless $query;
  
  # get necessary query params
  my $submitted_credits = $query->param('credits');
  my $voted_topic = $query->param('voted_t');
  my $config_topic = $query->param('conf_t');
  my $max_points = $query->param('max_p');
  
  # validate submitted input
  if( ($submitted_credits !~ m/^[1-9]{1}[0-9]*$/i) || ($voted_topic eq "") 
      || ($config_topic eq "")) {
    
    return _redirect('', $voted_topic);
  }
  
  ( $config{CONFWEB}, $config{CONFTOPIC} ) =
      $Foswiki::Plugins::SESSION->normalizeWebTopicName( '', $config_topic );
  
  $config{TOPICLOG} =
      $Foswiki::Plugins::SESSION->normalizeWebTopicName( $config{CONFWEB}, $config{CONFTOPIC}."Log" );
  
  # create hash of all voters
  _createVoterList();
  
  # create hash of voterlog
  _createPollLog();  
   
  # check if user max points reached to share for that topic
  if( ($max_points > 0) && 
      ((_getSharedPoints($voted_topic) + $submitted_credits) > $max_points)) {
    
    return _redirect('', $voted_topic);
  }
    
  # check if user has permission to vote AND has credit points left
  if((exists $pollUser{$config{USER}}) && ($pollUser{$config{USER}}{points} > 0)) {
     
    # get current datetime
    my $today = Foswiki::Time::formatTime(time, '$day. $month $year - $hours:$minutes:$seconds');
    
    # check if updating credits of current user succeeded
    if(_updatePollConfig($submitted_credits, $today)) {
      
      # save submitted credits of current user to credit log
      _updatePollLog($submitted_credits, $voted_topic, $today);
    }
  }
  
  # redirect to current topic
  return _redirect('', $voted_topic);
}

sub _getSharedPoints {
  my ($voted_topic) = @_;
  my $sharedPoints = 0;
  
  while ((my $date, my $points) = each(%{$pollLog{$config{USER}}{$voted_topic}})) {
    $sharedPoints += $points;
  } 
  
  
  
  return $sharedPoints;  
}

# redirects to specific topic
sub _redirect() {
  my( $voted_web, $voted_topic) = @_;
  
  ( $voted_web, $voted_topic) =
      $Foswiki::Plugins::SESSION->normalizeWebTopicName( $voted_web, $voted_topic );
      
  #return $Foswiki::Plugins::SESSION->redirect( Foswiki::Func::getViewUrl($voted_web, $voted_topic), 0 );
  return Foswiki::Func::redirectCgiQuery(
      undef, Foswiki::Func::getViewUrl($voted_web, $voted_topic), 0);
}

# returns specific error message
sub _error {
  my $mes = @_[0];
  my $error_label = "%RED%";
  my $error_label_end = "%ENDCOLOR%";  
  
  return $error_label.$mes.$error_label_end;
}

1;
