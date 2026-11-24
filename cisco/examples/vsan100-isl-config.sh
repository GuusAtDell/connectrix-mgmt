! ======================================================================
! VSAN 100 - inter-site ISL: Duesseldorf <-> Leverkusen
! ======================================================================
! Run the same commands on BOTH switches (D and LEV). Both port config
! files use the same ports for the VSAN 100 ISLs:
!   fc1/1, fc2/1  ->  port-channel 100
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
!   - VSAN 100 exists in the vsan database on both switches
!   - each switch has its own static domain ID in VSAN 100
!   - zone mode, default-zone policy and device-alias mode match on
!     both switches (otherwise the zone merge fails and VSAN 100 isolates)
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
interface fc1/1, fc2/1
 shutdown
exit

! --- Port-channel: E port, trunking on, VSAN 100 only ---
interface port-channel 100
 switchport mode E
 switchport trunk mode on
 switchport trunk allowed vsan 100
 channel mode active
exit

! --- Port VSAN of the ISL (same on both ends) ---
vsan database
 vsan 100 interface port-channel 100
exit

! --- Members: join the port-channel, then set buffer credits ---
! "force" copies the port-channel settings onto the member ports
interface fc1/1, fc2/1
 channel-group 100 force
 switchport fcrxbbcredit extended 2000
 no shutdown
exit

end

! --- Verification ---
show port-channel summary
show port-channel database interface port-channel 100
show interface port-channel 100
show interface port-channel 100 trunk vsan 100
show interface fc1/1 bbcredit
show topology vsan 100
show fcdomain domain-list vsan 100
show zone status vsan 100
! Repeat under load; "transitions to zero" should not keep increasing
show interface fc1/1 counters | include credit
show interface fc2/1 counters | include credit

copy running-config startup-config
