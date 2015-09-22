cmake_minimum_required( VERSION 2.8.4 )
project( htrsh.inc.sh )

file( GLOB inc_SH "*.inc.sh" )
file( GLOB inc_M "*.m" )

install( FILES ${inc_SH} DESTINATION bin )
install( FILES htrsh_load_alias.sh DESTINATION /etc/profile.d )
install( FILES ${inc_M} DESTINATION share/octave/site/m )
