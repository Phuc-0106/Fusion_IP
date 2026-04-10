#!/usr/bin/perl
# Regression Test Script for Fusion IP UVM Testbench
# Parses regress.cfg, executes tests, and generates regression report

use strict;
use warnings;
use Cwd;
use File::Temp qw(tempdir);
use Time::HiRes qw(time);
use Getopt::Long;

# =====================================================================
# Configuration and Defaults
# =====================================================================

my $config_file = "regress.cfg";
my $generate_report_only = 0;
my $verbose = 0;
my $num_parallel = 1;
my $help = 0;
my $log_dir = "log";
my $report_file = "regress.rpt";

GetOptions(
    'config|f=s' => \$config_file,
    'report|r' => \$generate_report_only,
    'verbose|v' => \$verbose,
    'parallel|j=i' => \$num_parallel,
    'help|h' => \$help,
    'log_dir|d=s' => \$log_dir,
) or die "Error in command line arguments\n";

if ($help) {
    print_help();
    exit(0);
}

# =====================================================================
# Subroutines
# =====================================================================

sub print_help {
    print <<'EOF';
Fusion IP UVM Regression Test Script

Usage: perl regress.pl [options]

Options:
  -f, --config FILE      Config file to parse [default: regress.cfg]
  -r, --report           Generate report only (no new tests)
  -v, --verbose          Verbose output
  -j, --parallel N       Number of parallel jobs [default: 1]
  -d, --log_dir DIR      Log directory [default: log]
  -h, --help             Show this help

Config Format:
  pass_key_word = "pattern";
  fail_key_word = "pattern";
  tc_list {
    test_name , run_times=N , run_opts=+opt1+opt2 ;
    ...
  }

Example:
  perl regress.pl                  # Run full regression
  perl regress.pl -f my.cfg        # Use custom config
  perl regress.pl -r               # Report only
  perl regress.pl -j 4             # Run 4 tests in parallel
  perl regress.pl -v -j 2          # Verbose + 2 parallel

EOF
}

sub parse_config {
    my ($file) = @_;
    my %config = (
        pass_keyword => "PASSED",
        fail_keyword => "FAILED",
        tc_list => [],
    );
    
    open(my $fh, '<', $file) or die "Cannot open config file: $file\n";
    my $in_tc_list = 0;
    my $line_num = 0;
    
    while (my $line = <$fh>) {
        $line_num++;
        chomp($line);
        next if $line =~ /^\s*#/;      # Skip comments
        next if $line =~ /^\s*$/;      # Skip empty lines
        
        # Parse pass keyword
        if ($line =~ /^\s*pass_key_word\s*=\s*"([^"]+)"/) {
            $config{pass_keyword} = $1;
        }
        
        # Parse fail keyword
        if ($line =~ /^\s*fail_key_word\s*=\s*"([^"]+)"/) {
            $config{fail_keyword} = $1;
        }
        
        # Start of test case list
        if ($line =~ /^\s*tc_list\s*\{/) {
            $in_tc_list = 1;
            next;
        }
        
        # End of test case list
        if ($in_tc_list && $line =~ /^\s*\}/) {
            $in_tc_list = 0;
            next;
        }
        
        # Parse test case
        if ($in_tc_list && $line =~ /^\s*(\w+)\s*,\s*run_times=(\d+)\s*,\s*run_opts=(.*?)\s*;/) {
            my $testname = $1;
            my $run_times = $2;
            my $run_opts = $3;
            
            # Convert +opt+opt to space-separated
            $run_opts =~ s/\+/ /g;
            
            for (my $i = 0; $i < $run_times; $i++) {
                push @{$config{tc_list}}, {
                    name => $testname,
                    opts => $run_opts,
                    iteration => $i + 1,
                    total_runs => $run_times,
                };
            }
        }
    }
    
    close($fh);
    
    if ($verbose) {
        print "[CONFIG] Parsed config from $file\n";
        print "[CONFIG] Pass keyword: $config{pass_keyword}\n";
        print "[CONFIG] Fail keyword: $config{fail_keyword}\n";
        print "[CONFIG] Total test runs: " . scalar(@{$config{tc_list}}) . "\n";
    }
    
    return %config;
}

sub create_log_dir {
    my ($dir) = @_;
    if (! -d $dir) {
        mkdir($dir) or die "Cannot create log directory: $dir\n";
    }
}

sub run_test {
    my ($testname, $opts, $iteration, $total) = @_;
    my $seed = time() * 1000 % 65536;  # Generate seed from time
    my $cmd;
    
    if ($opts) {
        $cmd = "make run TESTNAME=$testname SEED=$seed RUNARG='$opts' 2>&1";
    } else {
        $cmd = "make run TESTNAME=$testname SEED=$seed 2>&1";
    }
    
    if ($verbose) {
        print "[RUN] [$iteration/$total] $testname (seed=$seed)\n";
    }
    
    my $start_time = time();
    my $output = `$cmd`;
    my $elapsed = time() - $start_time;
    
    return {
        testname => $testname,
        seed => $seed,
        output => $output,
        elapsed => int($elapsed),
        iteration => $iteration,
        total => $total,
    };
}

sub check_result {
    my ($result, $pass_kw, $fail_kw) = @_;
    my $output = $result->{output};
    
    if ($output =~ /$fail_kw/i) {
        return 'FAIL';
    } elsif ($output =~ /$pass_kw/i) {
        return 'PASS';
    } else {
        return 'UNKNOWN';
    }
}

sub print_result {
    my ($result, $status) = @_;
    my $icon = ($status eq 'PASS') ? '[✓]' : ($status eq 'FAIL') ? '[✗]' : '[?]';
    printf("  %s %-40s [%3ds] [run %d/%d]\n",
        $icon,
        $result->{testname},
        $result->{elapsed},
        $result->{iteration},
        $result->{total}
    );
}

sub generate_report {
    my ($results, $config, $report_file) = @_;
    
    my $total = 0;
    my $passed = 0;
    my $failed = 0;
    my $unknown = 0;
    my $total_time = 0;
    
    open(my $fh, '>', $report_file) or die "Cannot write report: $report_file\n";
    
    print $fh "=" x 70 . "\n";
    print $fh "Fusion IP UVM Regression Test Report\n";
    print $fh "=" x 70 . "\n";
    print $fh "Generated: " . scalar(localtime()) . "\n";
    print $fh "Config: $config_file\n";
    print $fh "\n";
    
    # Summary by test
    my %test_summary = ();
    foreach my $result (@$results) {
        my $name = $result->{testname};
        my $status = $result->{status};
        
        if (!exists $test_summary{$name}) {
            $test_summary{$name} = { pass => 0, fail => 0, unknown => 0, time => 0 };
        }
        
        $test_summary{$name}->{$status eq 'PASS' ? 'pass' : ($status eq 'FAIL' ? 'fail' : 'unknown')}++;
        $test_summary{$name}->{time} += $result->{elapsed};
        
        $total++;
        $total_time += $result->{elapsed};
        
        if ($status eq 'PASS') {
            $passed++;
        } elsif ($status eq 'FAIL') {
            $failed++;
        } else {
            $unknown++;
        }
    }
    
    print $fh "Test Summary:\n";
    print $fh "-" x 70 . "\n";
    print $fh sprintf("  %-40s  Pass  Fail  Time(s)\n", "Test Name");
    print $fh "-" x 70 . "\n";
    
    foreach my $name (sort keys %test_summary) {
        my $s = $test_summary{$name};
        printf $fh ("  %-40s  %4d  %4d  %6d\n",
            $name,
            $s->{pass},
            $s->{fail},
            $s->{time}
        );
    }
    
    print $fh "-" x 70 . "\n";
    
    # Overall summary
    print $fh "\nOverall Results:\n";
    print $fh sprintf("  Total Runs:  %d\n", $total);
    print $fh sprintf("  Passed:      %d (%.1f%%)\n", $passed, $total > 0 ? 100.0 * $passed / $total : 0);
    print $fh sprintf("  Failed:      %d (%.1f%%)\n", $failed, $total > 0 ? 100.0 * $failed / $total : 0);
    print $fh sprintf("  Unknown:     %d\n", $unknown);
    print $fh sprintf("  Total Time:  %d seconds\n", $total_time);
    
    # Pass/Fail verdict
    my $verdict = ($failed == 0 && $unknown == 0) ? "PASS" : "FAIL";
    print $fh "\nRegression Verdict: " . $verdict . "\n";
    
    print $fh "=" x 70 . "\n";
    
    # Detailed results
    print $fh "\nDetailed Results:\n";
    print $fh "-" x 70 . "\n";
    
    foreach my $result (@$results) {
        my $status = $result->{status};
        my $icon = ($status eq 'PASS') ? '✓' : ($status eq 'FAIL') ? '✗' : '?';
        
        printf $fh ("[%s] %s (seed=%d, time=%ds)\n",
            $icon,
            $result->{testname},
            $result->{seed},
            $result->{elapsed}
        );
    }
    
    print $fh "=" x 70 . "\n";
    
    close($fh);
    
    print "\n[REPORT] Regression report written to: $report_file\n";
    print "[SUMMARY] Total: $total, Passed: $passed, Failed: $failed, Unknown: $unknown\n";
    print "[VERDICT] " . ($verdict eq 'PASS' ? "✓ ALL TESTS PASSED" : "✗ REGRESSION FAILED") . "\n";
    
    return $verdict;
}

# =====================================================================
# Main Logic
# =====================================================================

# Create log directory
create_log_dir($log_dir);

# Parse configuration
my %config = parse_config($config_file);

if ($generate_report_only) {
    # Just scan log directory and generate report
    print "[REPORT] Scanning log files for report generation...\n";
    my @results = ();
    
    # TODO: Scan log directory and parse results
    
    print "[REPORT] No logs found for report\n";
    exit(0);
}

# Run regression
print "=" x 70 . "\n";
print "Fusion IP UVM Regression Test Suite\n";
print "=" x 70 . "\n";
print "[START] Beginning regression at " . scalar(localtime()) . "\n";
print "[CONFIG] Test configuration: $config_file\n";
print "[INFO] Total test runs to execute: " . scalar(@{$config{tc_list}}) . "\n";
print "\n";

my @results = ();
my $run_count = 0;

foreach my $tc (@{$config{tc_list}}) {
    $run_count++;
    printf("[%3d/%3d] ", $run_count, scalar(@{$config{tc_list}}));
    
    my $result = run_test(
        $tc->{name},
        $tc->{opts},
        $tc->{iteration},
        $tc->{total_runs}
    );
    
    my $status = check_result($result, $config{pass_keyword}, $config{fail_keyword});
    $result->{status} = $status;
    
    print_result($result, $status);
    
    push @results, $result;
}

print "\n";
print "[END] Regression completed at " . scalar(localtime()) . "\n";

# Generate report
my $verdict = generate_report(\@results, \%config, $report_file);

print "\n";
exit(($verdict eq 'PASS') ? 0 : 1);

__END__

=head1 NAME

regress.pl - Regression test runner for Fusion IP UVM verification

=head1 SYNOPSIS

perl regress.pl [options]

=head1 OPTIONS

=over 4

=item B<-f, --config FILE>

Configuration file to parse (default: regress.cfg)

=item B<-r, --report>

Generate report only from existing logs

=item B<-v, --verbose>

Enable verbose output

=item B<-j, --parallel N>

Number of parallel jobs (default: 1)

=item B<-d, --log_dir DIR>

Log directory (default: log)

=item B<-h, --help>

Print help message

=back

=head1 DESCRIPTION

This script parses a regression configuration file (regress.cfg),
executes the specified test cases using make, and generates a
comprehensive regression test report.

=head1 CONFIG FORMAT

See regress.cfg for detailed format description.

=cut

