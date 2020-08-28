package Ocsinventory::Agent::Backend::OS::Generic::Users;

use strict;
use warnings;
use Data::Dumper;

sub check {
    my $params = shift;
    my $common = $params->{common};

    # Useless check for a posix system i guess
    my @who = `who 2>/dev/null`;
    my @last = `last 2>/dev/null`;

    if (($common->can_read("/etc/passwd") && $common->can_read("/etc/group")) || @who || @last ) {
        return 1;
    } else {
        return 0;
    }
}

# Initialise the distro entry
sub run {
    my $params = shift;
    my $common = $params->{common};

    my %users;

    # Logged on users
    for (`who`){
        my $user = $1 if /^(\S+)./;
        $common->addUser ({ LOGIN => $user });
    }

    # Local users
    foreach my $user (_getLocalUsers()) {
        push @{$users{$user->{GID}}}, $user->{LOGIN};
	    #delete $user->{GID};

        $common->addLocalUser({
            LOGIN => $user->{LOGIN},
            ID    => $user->{ID},
            GID   => $user->{GID},
            NAME  => $user->{NAME},
            HOME  => $user->{HOME},
            SHELL => $user->{SHELL}
        });
    }

    # Local groups with members
    foreach my $group (_getLocalGroups()) {
        push @{$group->{MEMBER}}, @{$users{$group->{ID}}} if $users{$group->{ID}};

        $common->addLocalGroup({
            ID     => $group->{ID},
            NAME   => $group->{NAME},
            MEMBER => $group->{MEMBER}
        });
    }

    # last logged user
    $common->setHardware(_getLast());
}

sub _getLocalUsers{

     open(my $fh, '<:encoding(UTF-8)', "/etc/passwd") or warn;
     my @userinfo=<$fh>;
     close($fh);

     my @users;

     foreach my $line (@userinfo){
         next if $line =~ /^#/;
         next if $line =~ /^[+-]/; # old format for external inclusion
         chomp $line;
         my ($login, undef, $uid, $gid, $gecos, $home, $shell) = split(/:/, $line);

         push @users, {
             LOGIN => $login,
             ID    => $uid,
             GID   => $gid,
             NAME  => $gecos,
             HOME  => $home,
             SHELL => $shell,
         };
     }

     return @users;

}

sub _getLocalGroups {

     open(my $fh, '<:encoding(UTF-8)', "/etc/group") or warn;
     my @groupinfo=<$fh>;
     close($fh);

     my @groups;

     foreach my $line (@groupinfo){
         next if $line =~ /^#/;
         chomp $line;
         my ($name, undef, $gid, $members) = split(/:/, $line);

         next unless $members;
         my @members = split(/,/, $members);

         push @groups, {
             ID     => $gid,
             NAME   => $name,
             MEMBER => @members,
         };
     }

     return @groups;

}

sub _getLast {
    
    my ($lastuser,$lastlogged);

    my @info=`last`;

    foreach my $last (@info) {
        chomp $last;
        next if $last =~ /^(reboot|shutdown)/;

        my @last = split(/\s+/, $last);
        next unless (@last);

        $lastuser = shift @last or next;

        # Found time on column starting as week day
        shift @last while ( @last > 3 && $last[0] !~ /^mon|tue|wed|thu|fri|sat|sun/i );
        $lastlogged = @last > 3 ? "@last[0..3]" : undef;
        last;
    }

    return unless $lastuser;

    return {
        LASTLOGGEDUSER     => $lastuser,
        DATELASTLOGGEDUSER => $lastlogged
    };
}

1;
