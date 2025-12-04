#!/bin/bash
perl tools/DoxygenFilterSystemVerilog/filter/idv_doxyfilter_sv.pl "$1" \
    | perl tools/sv_doxy_wrapper.pl
