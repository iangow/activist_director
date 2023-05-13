CREATE FUNCTION activist_director.parse_name(text) RETURNS activist_director.parsed_name
    LANGUAGE plperl
    AS $_X$
    my ($first_name, $middle_initial, $last_name, $suffix);
    my ($last_names, $first_names);

    # These suffixes are sometimes used without a preceding comma,
    # so we need to look at them separately from others
    $suffixes = 'JR|PH\.D\.|M\.D\.|ESQ\.|III|II';
    if (defined($_[0])) {
        # First, use commas to split into first and last names.
        # Because the * is greedy, the first (.*) will try to match
        # as much as possible, so the , that we match will be the last
        # one in the name
        if ($_[0] =~ /^(.*), (.*)$/) {
            ($last_names, $first_names) = ($1, $2);
        }

        # Use commas to break up the last_names variable.
        if ($last_names =~ /^([-\s'\w]+)(,(.*))?/) {
            ($last_name, $suffix) = ($1, $2);
        }

        # Use the suffixes variable to pull out suffixes without
        # preceding commas
        if ($last_name =~ /\s+($suffixes)/) {
            $suffix_alt = $1;
        }

        # Join the suffixes together, but delete leading
        # spaces and commas
        $suffix = $suffix_alt . ', ' . $suffix;
        $suffix =~ s/^[,\s]+//;
        $suffix =~ s/[,\s]+$//;

        # Remove suffixes from last name
        $last_name =~ s/\s+($suffixes)//;

        # Use spaces to parse out first and middle names
        if ($first_names =~ /([\w\.]+)\s*([\w\.]+)?/) {
                ($first_name, $middle_initial) = ($1, $2);
        }
    }

    return {first_name => $first_name, middle_initial => $middle_initial,
            last_name => $last_name, suffix => $suffix };

$_X$;
