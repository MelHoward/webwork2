################################################################################
# WeBWorK Online Homework Delivery System
# Copyright � 2000-2007 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork2/lib/WeBWorK/ContentGenerator/Problem.pm,v 1.225 2010/05/28 21:29:48 gage Exp $
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

# Created to house most output subroutines for Problem.pm to make that module more lightweight
# Now mostly defunct due to having moved most of the output declarations to the template
# -ghe3

package WeBWorK::ContentGenerator::ProblemUtil::ProblemUtil;
use base qw(WeBWorK);
use base qw(WeBWorK::ContentGenerator);

=head1 NAME

WeBWorK::ContentGenerator::ProblemUtil::ProblemUtil - contains a bunch of subroutines for generating output for the problem pages, especially those generated by Problem.pm

=cut

use strict;
use warnings;
#use CGI qw(-nosticky );
use WeBWorK::CGI;
use File::Path qw(rmtree);
use WeBWorK::Debug;
use WeBWorK::Form;
use WeBWorK::PG;
use WeBWorK::PG::ImageGenerator;
use WeBWorK::PG::IO;
use WeBWorK::Utils qw(readFile writeLog writeCourseLog encodeAnswers decodeAnswers
	ref2string makeTempDirectory path_is_subdir sortByName before after between jitar_problem_adjusted_status jitar_id_to_seq);
use WeBWorK::DB::Utils qw(global2user user2global);
use URI::Escape;
use WeBWorK::Authen::LTIAdvanced::SubmitGrade;
use WeBWorK::Utils::Tasks qw(fake_set fake_problem);

use Email::Simple;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP qw();
use Try::Tiny;


# process_and_log_answer subroutine.

# performs functions of processing and recording the answer given in the page.
# Also returns the appropriate scoreRecordedMessage.

sub process_and_log_answer{

	my $self = shift;  #type is ref($self) eq 'WeBWorK::ContentGenerator::Problem'
	my $r = $self->r;
	my $db = $r->db;
	my $effectiveUser = $r->param('effectiveUser');
	my $authz = $r->authz;


	my %will = %{ $self->{will} };
	my $submitAnswers = $self->{submitAnswers};
	my $problem = $self->{problem};
	my $pg = $self->{pg};
	my $set = $self->{set};
	my $urlpath = $r->urlpath;
	my $courseID = $urlpath->arg("courseID");

	# logging student answers
	my $pureProblem = $db->getUserProblem($problem->user_id, $problem->set_id, $problem->problem_id); # checked
	my $answer_log    = $self->{ce}->{courseFiles}->{logs}->{'answer_log'};

# 	my $isEssay = 0;
# 	my $scores2='';
# 	my $isEssay2=0;
#
# 	my %answersToStore2;
# 	my @answer_order2;
    my ($encoded_answer_string, $scores2, $isEssay2);
	my $scoreRecordedMessage = "";

	if ( defined($answer_log ) and defined($pureProblem)) {
		if ($submitAnswers && !$authz->hasPermissions($effectiveUser, "dont_log_past_answers")) {

################################################################
# new code (input is $pg)
#########################################
#
# 			my %answerHash2 = %{ $pg->{pgcore}->{PG_ANSWERS_HASH}};
#    			foreach my $ans_id (@{$pg->{flags}->{ANSWER_ENTRY_ORDER}//[]} ) {
#    				$scores2.= ($answerHash2{$ans_id}->{ans_eval}{rh_ans}{score}//0) >= 1 ? "1" : "0";
#    				$isEssay2 = 1 if ($answerHash2{$ans_id}->{ans_eval}{rh_ans}{type}//'') eq 'essay';
#    				foreach my $response_id ($answerHash2{$ans_id}->response_obj->response_labels) {
#    					$answersToStore2{$response_id} = $self->{formFields}->{$response_id};
#    				    push @answer_order2, $response_id;
#    				 }
#    			}
#    			my $answerString2 = '';
#    			foreach my $response_id (@answer_order2) {
#    				$answerString2.=($answersToStore2{$response_id}//'')."\t";
#    			}
#    			$answerString2=~s/\t$//; # remove last tab
	my ($answerString2);
	($answerString2,$encoded_answer_string, $scores2, $isEssay2) =
	    WeBWorK::ContentGenerator::ProblemUtil::ProblemUtil::create_ans_str_from_responses(
	      $self, $pg
	    );  # ref($self) eq WeBWorK::ContentGenerator::Problem
	        # ref($pg) eq "WeBWorK::PG::Local";
# end new code (output is answerString2, $scores, $isEssay)
################################################################
# 		    my $answerString = ""; my $scores = "";
# 			my %answerHash = %{ $pg->{answers} };
# 			# FIXME  this is the line 552 error.  make sure original student ans is defined.
# 			# The fact that it is not defined is probably due to an error in some answer evaluator.
# 			# But I think it is useful to suppress this error message in the log.
# 			foreach (sortByName(undef, keys %answerHash)) {
# 				my $orig_ans = $answerHash{$_}->{original_student_ans};
# 				my $student_ans = defined $orig_ans ? $orig_ans : '';
# 				$answerString  .= $student_ans."\t";
# 				# answer score *could* actually be a float, and this doesnt
# 				# allow for fractional answers :(
# 				$scores .= ($answerHash{$_}->{score}//0) >= 1 ? "1" : "0";
# 				$isEssay = 1 if ($answerHash{$_}->{type}//'') eq 'essay';
#
# 			}
#
# 			$answerString = '' unless defined($answerString); # insure string is defined.

##############################################################################
# check new code
			# experimental fix for past answers
			# notice that it grabs the student response from the html form fields rather than
			# from "original_student_ans" in the answerHash
			# The answer hash is inside ans_id.ans_eval.rh_ans
			#
#    			warn "answerString1: $answerString";
# 			warn "answerString2: $answerString2";
# 			warn "scores1: $scores";
# 			warn "scores2: $scores2";
# 			warn "isEssay1: $isEssay";
# 			warn "isEssay2: $isEssay2";

            # end experimental fix for past answers
##############################################################################
# store in answer_log   past answers file (user_id,set_id,problem_id,courseID,answerString,scores,source_file)
			my $timestamp = time();
			writeCourseLog($self->{ce}, "answer_log",
			        join("",
						'|', $problem->user_id,
						'|', $problem->set_id,
						'|', $problem->problem_id,
						'|', $scores2, "\t",
						$timestamp,"\t",
						$answerString2,
					),
			);

# add to PastAnswer db
			my $pastAnswer = $db->newPastAnswer();
			$pastAnswer->course_id($courseID);
			$pastAnswer->user_id($problem->user_id);
			$pastAnswer->set_id($problem->set_id);
			$pastAnswer->problem_id($problem->problem_id);
			$pastAnswer->timestamp($timestamp);
			$pastAnswer->scores($scores2);
			$pastAnswer->answer_string($answerString2);
			$pastAnswer->source_file($problem->source_file);
			$db->addPastAnswer($pastAnswer);


		}
	}

######################################################################
# this stores previous answers to the problem to
# provide "sticky answers"

	if ($submitAnswers) {
		# get a "pure" (unmerged) UserProblem to modify
		# this will be undefined if the problem has not been assigned to this user

		if (defined $pureProblem) {
			# store answers in DB for sticky answers
			my %answersToStore;
			#my %answerHash = %{ $pg->{answers} };
			# may not need to store answerHash explicitly since
			# it (usually?) has the same name as the first of the responses
			# $answersToStore{$_} = $self->{formFields}->{$_} foreach (keys %answerHash);
			# $answerHash{$_}->{original_student_ans} -- this may have been modified for fields with multiple values.
			# Don't use it!!
# 			my @answer_order;
# 			my %answerHash = %{ $pg->{pgcore}->{PG_ANSWERS_HASH}};
#    			foreach my $ans_id (@{$pg->{flags}->{ANSWER_ENTRY_ORDER}//[]} ) {
#    				foreach my $response_id ($answerHash{$ans_id}->response_obj->response_labels) {
#    					$answersToStore{$response_id} = $self->{formFields}->{$response_id};
#    				    push @answer_order, $response_id;
#    				 }
#    			}
#
			# There may be some more answers to store -- one which are auxiliary entries to a primary answer.  Evaluating
			# matrices works in this way, only the first answer triggers an answer evaluator, the rest are just inputs
			# however we need to store them.  Fortunately they are still in the input form.
			#my @extra_answer_names  = @{ $pg->{flags}->{KEPT_EXTRA_ANSWERS}//[]};
			#$answersToStore{$_} = $self->{formFields}->{$_} foreach  (@extra_answer_names);

			# Now let's encode these answers to store them -- append the extra answers to the end of answer entry order
			#my @answer_order = (@{$pg->{flags}->{ANSWER_ENTRY_ORDER}//[]}, @extra_answer_names);
			# %answerToStore and @answer_order are passed as references
			# because of profile for encodeAnswers

			# encodeAnswers creates a hash and uses Storage::nfreeze to serialize it
			# replaced by $encoded_answer_string
# 			my $answerString3 = encodeAnswers(%answersToStore2,
# 							 @answer_order2);

			# store last answer to database for use in "sticky" answers
			$problem->last_answer($encoded_answer_string);
			$pureProblem->last_answer($encoded_answer_string);
			$db->putUserProblem($pureProblem);

			# store state in DB if it makes sense
			if ($will{recordAnswers}) {
				$problem->status($pg->{state}->{recorded_score});
				$problem->sub_status($pg->{state}->{sub_recorded_score});
				$problem->attempted(1);
				$problem->num_correct($pg->{state}->{num_of_correct_ans});
				$problem->num_incorrect($pg->{state}->{num_of_incorrect_ans});
				$pureProblem->status($pg->{state}->{recorded_score});
				$pureProblem->sub_status($pg->{state}->{sub_recorded_score});
				$pureProblem->attempted(1);
				$pureProblem->num_correct($pg->{state}->{num_of_correct_ans});
				$pureProblem->num_incorrect($pg->{state}->{num_of_incorrect_ans});

				#add flags for an essay question.  If its an essay question and
				# we are submitting then there could be potential changes, and it should
				# be flaged as needing grading
				# we shoudl also check for the appropriate flag in the global problem and set it

				if ($isEssay2 && $pureProblem->{flags} !~ /needs_grading/) {
				    $pureProblem->{flags} =~ s/graded,//;
				    $pureProblem->{flags} .= "needs_grading,";
				}

				my $globalProblem = $db->getGlobalProblem($problem->set_id, $problem->problem_id);
				if ($isEssay2 && $globalProblem->{flags} !~ /essay/) {
				    $globalProblem->{flags} .= "essay,";
				    $db->putGlobalProblem($globalProblem);
				} elsif (!$isEssay2 && $globalProblem->{flags} =~ /essay/) {
				    $globalProblem->{flags} =~ s/essay,//;
				    $db->putGlobalProblem($globalProblem);
				}

				if ($db->putUserProblem($pureProblem)) {
					$scoreRecordedMessage = $r->maketext("Your score was recorded.");
				} else {
					$scoreRecordedMessage = $r->maketext("Your score was not recorded because there was a failure in storing the problem record to the database.");
				}
				# write to the transaction log, just to make sure
				writeLog($self->{ce}, "transaction",
					$problem->problem_id."\t".
					$problem->set_id."\t".
					$problem->user_id."\t".
					$problem->source_file."\t".
					$problem->value."\t".
					$problem->max_attempts."\t".
					$problem->problem_seed."\t".
					$pureProblem->status."\t".
					$pureProblem->attempted."\t".
					$pureProblem->last_answer."\t".
					$pureProblem->num_correct."\t".
					$pureProblem->num_incorrect
					);

				#Try to update the student score on the LMS
				# if that option is enabled.
				my $LTIGradeMode = $self->{ce}->{LTIGradeMode} // '';
				if ($LTIGradeMode && $self->{ce}->{LTIGradeOnSubmit}) {
				  my $grader = WeBWorK::Authen::LTIAdvanced::SubmitGrade->new($r);
				  if ($LTIGradeMode eq 'course') {
				    if ($grader->submit_course_grade($problem->user_id)) {
				      $scoreRecordedMessage .= $r->maketext("Your score was successfully sent to the LMS");
				    } else {
				      $scoreRecordedMessage .= $r->maketext("Your score was not successfully sent to the LMS");
				    }
				  } elsif ($LTIGradeMode eq 'homework') {
				    if ($grader->submit_set_grade($problem->user_id, $problem->set_id)) {
				      $scoreRecordedMessage .= $r->maketext("Your score was successfully sent to the LMS");
				    } else {
				      $scoreRecordedMessage .= $r->maketext("Your score was not successfully sent to the LMS");
				    }
				  }
				}

			} else {
				if (before($set->open_date) or after($set->due_date)) {
					$scoreRecordedMessage = $r->maketext("Your score was not recorded because this homework set is closed.");
				} else {
					$scoreRecordedMessage = $r->maketext("Your score was not recorded.");
				}
			}
		} else {
			$scoreRecordedMessage = $r->maketext("Your score was not recorded because this problem has not been assigned to you.");
		}
	}


	$self->{scoreRecordedMessage} = $scoreRecordedMessage;
	return $scoreRecordedMessage;
}

# create answer string from responses hash
# ($ansString, $encoded_ans_string, $scores, $isEssay) = create_ans_str_from_responses($problem, $pg)
#
# input: ref($pg)eq 'WeBWorK::PG::Local'
#        ref($problem)eq 'WeBWorK::ContentGenerator::Problem
# output:  (str, str, str)

sub create_ans_str_from_responses {
	my $problem = shift;  #  ref($problem) eq 'WeBWorK::ContentGenerator::Problem'
	                   	  #  must contain $self->{formFields}->{$response_id}
	my $pg = shift;       # ref($pg) eq 'WeBWorK::PG::Local'
	#warn "create_ans_str_from_responses pg has type ", ref($pg);
	my $scores2='';
	my $isEssay2=0;
	my %answersToStore2;
	my @answer_order2;

	my %answerHash2 = %{ $pg->{pgcore}->{PG_ANSWERS_HASH}};
	foreach my $ans_id (@{$pg->{flags}->{ANSWER_ENTRY_ORDER}//[]} ) {
		$scores2.= ($answerHash2{$ans_id}->{ans_eval}{rh_ans}{score}//0) >= 1 ? "1" : "0";
		$isEssay2 = 1 if ($answerHash2{$ans_id}->{ans_eval}{rh_ans}{type}//'') eq 'essay';
		foreach my $response_id ($answerHash2{$ans_id}->response_obj->response_labels) {
			$answersToStore2{$response_id} = $problem->{formFields}->{$response_id};
			push @answer_order2, $response_id;
		 }
	}
	my $answerString2 = '';
	foreach my $response_id (@answer_order2) {
		$answerString2.=($answersToStore2{$response_id}//'')."\t";
	}
	$answerString2=~s/\t$//; # remove last tab

   	my $encoded_answer_string = encodeAnswers(%answersToStore2,
							 @answer_order2);

	return ($answerString2,$encoded_answer_string, $scores2,$isEssay2);
}

# process_editorLink subroutine

# Creates and returns the proper editor link for the current website.  Also checks for translation errors and prints an error message and returning a false value if one is detected.

sub process_editorLink{

	my $self = shift;

	my $set = $self->{set};
	my $problem = $self->{problem};
	my $pg = $self->{pg};

	my $r = $self->r;

	my $authz = $r->authz;
	my $urlpath = $r->urlpath;
	my $user = $r->param('user');

	my $courseName = $urlpath->arg("courseID");

	# FIXME: move editor link to top, next to problem number.
	# format as "[edit]" like we're doing with course info file, etc.
	# add edit link for set as well.
	my $editorLink = "";
	# if we are here without a real homework set, carry that through
	my $forced_field = [];
	$forced_field = ['sourceFilePath' =>  $r->param("sourceFilePath")] if
		($set->set_id eq 'Undefined_Set');
	if ($authz->hasPermissions($user, "modify_problem_sets")) {
		my $editorPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::Instructor::PGProblemEditor2",
			courseID => $courseName, setID => $set->set_id, problemID => $problem->problem_id);
		my $editorURL = $self->systemLink($editorPage, params=>$forced_field);
		$editorLink = CGI::p(CGI::a({href=>$editorURL,target =>'WW_Editor'}, "Edit this problem"));
	}

	##### translation errors? #####

	if ($pg->{flags}->{error_flag}) {
		if ($authz->hasPermissions($user, "view_problem_debugging_info")) {
			print $self->errorOutput($pg->{errors}, $pg->{body_text});
		} else {
			print $self->errorOutput($pg->{errors}, "You do not have permission to view the details of this error.");
		}
		print $editorLink;
		return "permission_error";
	}
	else{
		return $editorLink;
	}
}

# output_JS subroutine

# prints out the legacy/vendor/wz_tooltip.js script for the current site.

sub output_JS{

	my $self = shift;
	my $r = $self->r;
	my $ce = $r->ce;

	my $site_url = $ce->{webworkURLs}->{htdocs};
	print CGI::start_script({type=>"text/javascript", src=>"$site_url/js/legacy/vendor/wz_tooltip.js"}), CGI::end_script();
}

# output_summary subroutine

# prints out summary information for the problem pages.

# sub output_summary{
# 
# 	my $self = shift;
# 
# 	my $editMode = $self->{editMode};
# 	my $problem = $self->{problem};
# 	my $pg = $self->{pg};
# 	my $submitAnswers = $self->{submitAnswers};
# 	my %will = %{ $self->{will} };
# 	my $checkAnswers = $self->{checkAnswers};
# 	my $previewAnswers = $self->{previewAnswers};
# 
# 	my $r = $self->r;
# 
# 	my $authz = $r->authz;
# 	my $user = $r->param('user');
# 
# 	# custom message for editor
# 	if ($authz->hasPermissions($user, "modify_problem_sets") and defined $editMode) {
# 		if ($editMode eq "temporaryFile") {
# 			print CGI::p(CGI::div({class=>'temporaryFile'}, "Viewing temporary file: ", $problem->source_file));
# 		} elsif ($editMode eq "savedFile") {
# 			# taken care of in the initialization phase
# 		}
# 	}
# 	print CGI::start_div({class=>"problemHeader"});
# 
# 
# 	# attempt summary
# 	#FIXME -- the following is a kludge:  if showPartialCorrectAnswers is negative don't show anything.
# 	# until after the due date
# 	# do I need to check $will{showCorrectAnswers} to make preflight work??
# 	if (($pg->{flags}->{showPartialCorrectAnswers} >= 0 and $submitAnswers) ) {
# 		# print this if user submitted answers OR requested correct answers
# 
# 		print $self->attemptResults($pg, 1,
# 			$will{showCorrectAnswers},
# 			$pg->{flags}->{showPartialCorrectAnswers}, 1, 1);
# 	} elsif ($checkAnswers) {
# 		# print this if user previewed answers
# 		print CGI::div({class=>'ResultsWithError'},"ANSWERS ONLY CHECKED -- ANSWERS NOT RECORDED"), CGI::br();
# 		print $self->attemptResults($pg, 1, $will{showCorrectAnswers}, 1, 1, 1);
# 			# show attempt answers
# 			# show correct answers if asked
# 			# show attempt results (correctness)
# 			# show attempt previews
# 	} elsif ($previewAnswers) {
# 		# print this if user previewed answers
# 		print CGI::div({class=>'ResultsWithError'},"PREVIEW ONLY -- ANSWERS NOT RECORDED"),CGI::br(),$self->attemptResults($pg, 1, 0, 0, 0, 1);
# 			# show attempt answers
# 			# don't show correct answers
# 			# don't show attempt results (correctness)
# 			# show attempt previews
# 	}
# 
# 	print CGI::end_div();
# }

# output_CSS subroutine

# prints the CSS scripts to page.  Does some PERL trickery to form the styles
# for the correct answers and the incorrect answers (which may be substituted with JS sometime in the future).

# sub output_CSS{
#
# 	my $self = shift;
# 	my $r = $self->r;
# 	my $ce = $r->ce;
# 	my $pg = $self->{pg};
#
# 	# always show colors for checkAnswers
# 	# show colors for submit answer if
# 	if (($self->{checkAnswers}) or ($self->{submitAnswers} and $pg->{flags}->{showPartialCorrectAnswers}) ) {
# 		print CGI::start_style({type=>"text/css"});
# 		print	'#'.join(', #', @{ $self->{correct_ids} }), $ce->{pg}{options}{correct_answer}   if ref( $self->{correct_ids}  )=~/ARRAY/;   #correct  green
# 		print	'#'.join(', #', @{ $self->{incorrect_ids} }), $ce->{pg}{options}{incorrect_answer} if ref( $self->{incorrect_ids})=~/ARRAY/; #incorrect  reddish
# 		print	CGI::end_style();
# 	}
# }

# output_main_form subroutine.

# prints out the main form for the page.  This particular subroutine also takes in $editorLink and $scoreRecordedMessage as required parameters. Also uses CGI_labeled_input for its input elements for accessibility reasons.  Also prints out the score summary where applicable.

sub output_main_form{

	my $self = shift;
	my $editorLink = shift;

	my $r = $self->r;
	my $pg = $self->{pg};
	my $problem = $self->{problem};
	my $set = $self->{set};
	my $submitAnswers = $self->{submitAnswers};

	my $db = $r->db;
	my $ce = $r->ce;
	my $user = $r->param('user');
	my $effectiveUser = $r->{'effectiveUser'};

	my %can = %{ $self->{can} };
	my %will = %{ $self->{will} };

	print "\n";
	print CGI::start_form(-method=>"POST", -action=> $r->uri,-name=>"problemMainForm", onsubmit=>"submitAction()");
	print $self->hidden_authen_fields;
	print CGI::end_form();
}

# output_footer subroutine

# prints out the footer elements to the page.

sub output_footer{

	my $self = shift;
	my $r = $self->r;
	my $problem = $self->{problem};
	my $pg = $self->{pg};
	my %will = %{ $self->{will} };

	my $authz = $r->authz;
	my $urlpath = $r->urlpath;
	my $user = $r->param('user');

	my $courseName = $urlpath->arg("courseID");

	print CGI::start_div({class=>"problemFooter"});


	my $pastAnswersPage = $urlpath->newFromModule("WeBWorK::ContentGenerator::Instructor::ShowAnswers",
		courseID => $courseName);
	my $showPastAnswersURL = $self->systemLink($pastAnswersPage, authen => 0); # no authen info for form action

	# print answer inspection button
	if ($authz->hasPermissions($user, "view_answers")) {
		print "\n",
			CGI::start_form(-method=>"POST",-action=>$showPastAnswersURL,-target=>"WW_Info"),"\n",
			$self->hidden_authen_fields,"\n",
			CGI::hidden(-name => 'courseID',  -value=>$courseName), "\n",
			CGI::hidden(-name => 'problemID', -value=>$problem->problem_id), "\n",
			CGI::hidden(-name => 'setID',  -value=>$problem->set_id), "\n",
			CGI::hidden(-name => 'studentUser',    -value=>$problem->user_id), "\n",
			CGI::p( {-align=>"left"},
				CGI::submit(-name => 'action',  -value=>'Show Past Answers')
			), "\n",
			CGI::end_form();
	}


	print $self->feedbackMacro(
		module             => __PACKAGE__,
		set                => $self->{set}->set_id,
		problem            => $problem->problem_id,
		displayMode        => $self->{displayMode},
		showOldAnswers     => $will{showOldAnswers},
		showCorrectAnswers => $will{showCorrectAnswers},
		showHints          => $will{showHints},
		showSolutions      => $will{showSolutions},
		pg_object          => $pg,
	);

	print CGI::end_div();
}

# check_invalid subroutine

# checks to see if the current problem set is valid for the current user, returns "valid" if it is and an error message if it's not.

sub check_invalid{

	my $self = shift;
	my $r = $self->r;
	my $urlpath = $r->urlpath;
	my $effectiveUser = $r->param('effectiveUser');

	if ( $self->{invalidSet} ) {
		return CGI::div({class=>"ResultsWithError"},
				CGI::p("The selected problem set (" .
				       $urlpath->arg("setID") . ") is not " .
				       "a valid set for $effectiveUser:"),
				CGI::p($self->{invalidSet}));
	}

	elsif ($self->{invalidProblem}) {
		return CGI::div({class=>"ResultsWithError"},
			CGI::p("The selected problem (" . $urlpath->arg("problemID") . ") is not a valid problem for set " . $self->{set}->set_id . "."));
	}
	else{
		return "valid";
	}

}

sub test{
	print "test";
}

# if you provide this subroutine with a userProblem it will notify the
# instructors of the course that the student has finished the problem,
# and its children, and did not get 100%
sub jitar_send_warning_email {
    my $self = shift;
    my $userProblem = shift;

    my $r= $self->r;
    my $ce = $r->ce;
    my $db = $r->db;
    my $authz = $r->authz;
    my $urlpath    = $r->urlpath;
    my $courseID = $urlpath->arg("courseID");
    my $userID = $userProblem->user_id;
    my $setID = $userProblem->set_id;
    my $problemID = $userProblem->problem_id;

    my $status = jitar_problem_adjusted_status($userProblem,$r->db);
    $status = eval{ sprintf("%.0f%%", $status * 100)}; # round to whole number

    my $user = $db->getUser($userID);

    debug("Couldn't get user $userID from database") unless $user;

    my $emailableURL = $self->systemLink(
	$urlpath->newFromModule("WeBWorK::ContentGenerator::Problem", $r,
				courseID => $courseID, setID => $setID, problemID => $problemID), params=>{effectiveUser=>$userID}, use_abs_url=>1);


	my @recipients;
        # send to all users with permission to score_sets an email address
	# DBFIXME iterator?
	foreach my $rcptName ($db->listUsers()) {
		if ($authz->hasPermissions($rcptName, "score_sets")) {
			my $rcpt = $db->getUser($rcptName); # checked
			next if $ce->{feedback_by_section} and defined $user
			    and defined $rcpt->section and defined $user->section
			    and $rcpt->section ne $user->section;
			if ($rcpt and $rcpt->email_address) {
			    push @recipients, $rcpt->rfc822_mailbox;
			}
		}
	}

    my $sender;
    if ($user->email_address) {
	$sender = $user->rfc822_mailbox;
    } elsif ($user->full_name) {
	$sender = $user->full_name;
    } else {
	$sender = $userID;
    }

    $problemID = join('.',jitar_id_to_seq($problemID));


    my %subject_map = (
	'c' => $courseID,
	'u' => $userID,
	's' => $setID,
	'p' => $problemID,
	'x' => $user->section,
	'r' => $user->recitation,
	'%' => '%',
	);
    my $chars = join("", keys %subject_map);
    my $subject = $ce->{mail}{feedbackSubjectFormat}
    || "WeBWorK question from %c: %u set %s/prob %p"; # default if not entered
    $subject =~ s/%([$chars])/defined $subject_map{$1} ? $subject_map{$1} : ""/eg;

# 		my $transport = Email::Sender::Transport::SMTP->new({
# 			host => $ce->{mail}->{smtpServer},
# 			ssl => $ce->{mail}->{tls_allowed}//1, ## turn on ssl security
# 			timeout => $ce->{mail}->{smtpTimeout}
# 		});
# 

#           createEmailSenderTransportSMTP is defined in ContentGenerator
		my $transport = $self->createEmailSenderTransportSMTP();
		my $email = Email::Simple->create(header => [
			"To" => join(",", @recipients),
			"From" => $sender,
			"Subject" => $subject
		]);

		## extra headers
		$email->header_set("X-WeBWorK-Course: ",$courseID) if defined $courseID;
		if ($user) {
			$email->header_set("X-WeBWorK-User: ",$user->user_id);
			$email->header_set("X-WeBWorK-Section: ",$user->section);
			$email->header_set("X-WeBWorK-Recitation: ",$user->recitation);
		}
		$email->header_set("X-WeBWorK-Set: ",$setID) if defined $setID;
		$email->header_set("X-WeBWorK-Problem: ",$problemID) if defined $problemID;

    my $full_name = $user->full_name;
    my $email_address = $user->email_address;
    my $student_id = $user->student_id;
    my $section = $user->section;
    my $recitation = $user->recitation;
    my $comment = $user->comment;

    # print message
my $msg = qq/
This  message was automatically generated by WeBWorK.

User $full_name ($userID) has not sucessfully completed the review for problem $problemID in set $setID.  Their final adjusted score on the problem is $status.

Click this link to visit the problem: $emailableURL

User ID:    $userID
Name:       $full_name
Email:      $email_address
Student ID: $student_id
Section:    $section
Recitation: $recitation
Comment:    $comment
/;

  	$email->body_set($msg);

		## try to send the email

		try {
			sendmail($email,{transport => $transport});
				debug("Successfully sent JITAR alert message");
		} catch {
      $r->log_error("Failed to send JITAR alert message: $_");
		};


    return "";
}

1;
