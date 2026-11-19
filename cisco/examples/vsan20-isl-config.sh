! ======================================================================
! VSAN 20 - inter-site ISL: Duesseldorf <-> Leverkusen
! ======================================================================
! Run the same commands on BOTH switches (D and LEV). Both port config
! files use the same ports for the VSAN 20 ISLs:
!   fc3/48, fc4/48, fc7/48, fc8/48  ->  port-channel 20
!
! Buffer credit sizing (rule of thumb: credits ~= km x Gbps / 2 for
! full 2 KB frames; double that for realistic ~1 KB average frames):
!   Straight-line distance ~35 km, fibre route assumed ~50 km
!   50 km x 32 Gbps / 2 = 800 (full frames) -> 1600 (realistic)
!   + ~25% margin                             -> 2000 credits per port
!   At 16G this would be ~1000. Recalculate once the carrier confirms
!   the real fibre route length.
!
! Prerequisites (not in this script):
!   - VSAN 20 exists in the vsan database on both switches
!   - each switch has its own static domain ID in VSAN 20
!   - zone mode, default-zone policy and device-alias mode match on
!     both switches (otherwise the zone merge fails and VSAN 20 isolates)
!   - extended-reach optics or DWDM (long-wave only reaches 10 km)
!
! Check before use: command syntax for extended credits differs between
! NX-OS releases and modules, and may need the ENTERPRISE_PKG license.
! Check the per-port-group credit pool with: show port-resources module <n>
! ======================================================================

! Suppress y/n prompts (e.g. "switchport trunk allowed vsan" replacing
! the existing allowed list) so a scripted SSH push does not hang
terminal dont-ask

configure terminal

! --- Enable extended receive buffer credits ---
feature fcrxbbcredit extended

! --- Shut member ports while changing channel and credit settings ---
interface fc3/48, fc4/48, fc7/48, fc8/48
 shutdown
exit

! --- Port-channel: E port, trunking on, VSAN 20 only ---
interface port-channel 20
 switchport mode E
 switchport trunk mode on
 switchport trunk allowed vsan 20
 channel mode active
exit

! --- Port VSAN of the ISL (same on both ends) ---
vsan database
 vsan 20 interface port-channel 20
exit

! --- Members: join the port-channel, then set buffer credits ---
! "force" copies the port-channel settings onto the member ports
interface fc3/48, fc4/48, fc7/48, fc8/48
 channel-group 20 force
 switchport fcrxbbcredit extended 2000
 no shutdown
exit

end

! --- Verification ---
show port-channel summary
show port-channel database interface port-channel 20
show interface port-channel 20
show interface port-channel 20 trunk vsan 20
show interface fc3/48 bbcredit
show topology vsan 20
show fcdomain domain-list vsan 20
show zone status vsan 20
! Repeat under load; "transitions to zero" should not keep increasing
show interface fc3/48 counters | include credit
show interface fc4/48 counters | include credit
show interface fc7/48 counters | include credit
show interface fc8/48 counters | include credit

copy running-config startup-config
