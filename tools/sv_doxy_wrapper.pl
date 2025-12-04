#!/usr/bin/env perl
##############################################################################
# @file sv_doxy_wrapper.pl
# @brief SystemVerilog to Doxygen Preprocessor
#
# This script preprocesses SystemVerilog code to improve compatibility with
# Doxygen documentation generation. It performs several transformations:
#
# 1. Removes bit-range specifications like [15:0], [4:0], [0:0]
# 2. Cleans up range fragments like ":0]" that may remain after processing
# 3. Removes stray colons at the beginning of lines
# 4. Optionally converts SystemVerilog types to C-like types for better
#    Doxygen recognition
#
# @usage
#    cat input.sv | perl sv_doxy_wrapper.pl > output.sv
#    doxygen -g Doxyfile
#    doxygen Doxyfile
#
# @note This is particularly useful when documenting mixed-language projects
#       containing SystemVerilog code with Doxygen.
#
# @author
# @date
# @version 1.0
##############################################################################

use strict;
use warnings;

##############################################################################
# @brief Main processing loop
#
# Reads SystemVerilog code from STDIN, applies transformations, and writes
# to STDOUT.
#
# @details The transformations include:
#          - Removing bit-range specifications for cleaner documentation
#          - Cleaning up syntax fragments that confuse Doxygen
#          - Optional type conversion for better Doxygen compatibility
#
# @return Exit code 0 on success
##############################################################################
while (my $line = <STDIN>) {

    # 1) Remove bit-range specifications: [15:0], [4:0], [0:0], etc.
    #    This includes handling for both decimal and tick-based literals
    $line =~ s/\[\s*[\d']+\s*:\s*[\d']+\s*\]//g;

    # 2) Clean up range fragments like ":0]" that may remain after processing
    #    These can appear when ranges are partially processed or malformed
    $line =~ s/:\s*\d+\]\s*//g;

    # 3) Remove stray colon at the beginning of lines
    #    Often appears after removing bit-range specifications
    $line =~ s/^(\s*):\s+/$1/;

    # 4) (Optional) Convert SystemVerilog types to C-like types
    #    Improves Doxygen's ability to recognize and document types
    $line =~ s/\blogic\b/unsigned int/g;
    $line =~ s/\bbit\b/unsigned int/g;
    $line =~ s/\breg\b/unsigned int/g;

    # Output the processed line
    print $line;
}

exit 0;
