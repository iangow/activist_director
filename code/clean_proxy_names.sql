CREATE FUNCTION activist_director.clean_proxy_names(names text) RETURNS text
    LANGUAGE plperl
    AS $_X$
    $temp = $_[0];

    # Get rid of multiple spaces
    # Don't use \s, as newlines should not be replaced.
    $temp =~ s/ {2,}/ /g;

    # Split on word " and "
    $temp =~ s/,?\s+and\s+/\n/gi;

    # Replace newlines with semi-colons
    $temp =~ s/\s*\n\s*/;/g;

    $temp =~ s/\s*\(*\d+[.)]*\s*//g;
    $temp =~ s/,\s*$//;
    return $temp;
$_X$;
