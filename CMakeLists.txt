cmake_minimum_required( VERSION 2.8.4 )
project( htrsh.inc.sh )

#set( SYSCONFDIR /etc CACHE PATH "System configuration directory" )
#file( TO_NATIVE_PATH "${SYSCONFDIR}" SYSCONFDIR )

file( GLOB inc_SH "*.inc.sh" )
file( GLOB inc_M "*.m" )

install( PROGRAMS ${inc_SH} DESTINATION bin )
#install( FILES htrsh_load_alias.sh DESTINATION ${SYSCONFDIR}/profile.d )
install( FILES ${inc_M} DESTINATION share/octave/site/m )
