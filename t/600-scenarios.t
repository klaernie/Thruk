use strict;
use warnings;
use Test::More;
use Cwd qw/cwd/;
use Time::HiRes qw/gettimeofday tv_interval/;

BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
    plan skip_all => 'docker required' unless TestUtils::has_util('docker');
    plan skip_all => 'docker-compose required' unless TestUtils::has_util('docker-compose');
}

my $filter;
if($0 =~ m/scenario\-(.*)\.t$/mx) {
    $filter = 't/scenarios/'.$1;
}

use_ok("Thruk::Utils");
use_ok("Thruk::Utils::IO");

my $verbose = $ENV{'HARNESS_IS_VERBOSE'} ? 1 : undef;
my $pwd  = cwd();
my $make = $ENV{'MAKE'} || 'make';
my $scenarios = [map($_ =~ s/\/\.$//gmx && $_, split/\n/mx, `ls -1d t/scenarios/*/.`)];

for my $dir (@{$scenarios}) {
    next if $filter && $filter ne $dir;
    next if $dir =~ m/\/_/mx;
    chdir($dir);
    _run($dir, "clean");
    chdir($pwd);
}

for my $dir (@{$scenarios}) {
    if($filter) {
        # test specific scenario
        next if $filter ne $dir;
        if($dir =~ /e2e$/mx && !$ENV{'THRUK_TEST_E2E'}) {
            diag('E2E tests skiped, set THRUK_TEST_E2E env to run them');
            next;
        }
        chdir($dir);
        my $archive = [];
        for my $step (qw/clean update prepare wait_start test_verbose clean/) {
            _run($dir, $step, $archive);
        }
        chdir($pwd);
    }
    else {
        # simply test if we have a specific test case for all required scenarios
        next if $dir =~ /nagios4/mx;
        my $dirname = $dir;
        $dirname =~ s%^.*/%%gmx;
        my $filename = 't/610-scenario-'.$dirname.'.t';
        if(-e $filename) {
            ok(1, "test case for $dirname exists");
        } elsif($dirname =~ m/^pentest_/mx) {
            ok(1, "no test case for pentests required");
        } elsif($dirname =~ m/^_/mx) {
            ok(1, "no test case for common folder required");
        } else {
            fail("missing test case file: ".$filename);
        }
    }
}

# make simple normal final request since the tests kill existing lmd childs and upcoming
# tests will fail if there is a startup message on stderr
TestUtils::test_page( url => '/thruk/cgi-bin/extinfo.cgi?type=0', follow => 1);

done_testing();

sub _run {
    my($dir, $step, $archive) = @_;

    my $t0 = [gettimeofday];
    ok(1, "$dir: running make $step");
    my($rc, $out) = Thruk::Utils::IO::cmd(undef, [$make, $step], undef, ($verbose ? '## ' : undef));
    is($rc, 0, sprintf("step %s complete, rc=%d duration=%.1fsec", $step, $rc, tv_interval ($t0)));
    push @{$archive}, [$step, $rc, $out];
    # already printed in verbose mode
    if(!$verbose && $rc != 0) {
        for my $a (@{$archive}) {
            diag("*** make output ************************************************************************************");
            diag("step: ".$a->[0]);
            diag("rc:   ".$a->[1]);
            diag($a->[2]);
            diag("****************************************************************************************************");
        }
    };
    if($step eq "prepare" && $rc != 0) {
        diag(`docker ps`);
        BAIL_OUT("$step failed");
    }
    return($rc, $out);
}
