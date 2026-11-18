configure terminal
! example only: live discovery is not available in generate-script mode
! show interface brief | include ^fc
interface fcX/Y
 shutdown
exit
interface fc1/1
 switchport mode E
 switchport trunk mode on
 switchport trunk allowed vsan 100
 no shutdown
exit
interface fc1/3
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc1/4
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc1/5
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc1/6
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc1/7
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc1/8
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc1/10
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/11
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/13
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/14
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/15
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/19
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/20
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/22
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/29
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/30
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/31
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/32
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/39
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/40
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc1/43
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/1
 switchport mode E
 switchport trunk mode on
 switchport trunk allowed vsan 100
 no shutdown
exit
interface fc2/2
 switchport mode F
 switchport access vsan 100
 no shutdown
exit
interface fc2/3
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc2/4
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc2/5
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc2/6
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc2/7
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc2/8
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc2/9
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/10
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/11
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/13
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/14
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/15
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/17
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/19
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/20
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/23
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/29
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/30
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/31
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/32
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/39
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/40
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc2/43
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/1
 switchport mode F
 switchport access vsan 100
 no shutdown
exit
interface fc3/2
 switchport mode F
 switchport access vsan 100
 no shutdown
exit
interface fc3/3
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc3/4
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc3/5
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc3/6
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc3/7
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc3/8
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc3/9
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/10
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/11
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/13
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/14
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/15
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/16
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/18
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/20
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/29
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/30
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/31
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/32
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/39
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/40
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/43
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/44
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc3/48
 switchport mode E
 switchport trunk mode on
 switchport trunk allowed vsan 20
 no shutdown
exit
interface fc4/1
 switchport mode F
 switchport access vsan 100
 no shutdown
exit
interface fc4/3
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc4/4
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc4/5
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc4/6
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc4/7
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc4/8
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc4/9
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/10
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/11
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/13
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/15
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/16
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/19
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/20
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/21
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/23
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/29
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/30
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/31
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/32
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/39
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/40
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/43
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/44
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc4/48
 switchport mode E
 switchport trunk mode on
 switchport trunk allowed vsan 20
 no shutdown
exit
interface fc7/1
 switchport mode F
 switchport access vsan 100
 no shutdown
exit
interface fc7/3
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc7/4
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc7/5
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc7/6
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc7/7
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc7/8
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc7/9
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/10
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/11
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/13
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/14
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/15
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/16
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/17
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/18
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/19
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/20
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/22
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/25
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/27
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/28
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/29
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/30
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/31
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/32
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/39
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/40
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/41
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/42
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/43
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/44
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc7/48
 switchport mode E
 switchport trunk mode on
 switchport trunk allowed vsan 20
 no shutdown
exit
interface fc8/1
 switchport mode F
 switchport access vsan 100
 no shutdown
exit
interface fc8/3
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc8/4
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc8/5
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc8/6
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc8/7
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc8/8
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc8/9
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/11
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/12
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/13
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/14
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/15
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/17
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/18
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/19
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/20
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/23
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/25
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/27
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/28
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/29
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/30
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/31
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/32
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/39
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/40
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/41
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/42
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/43
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/44
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc8/48
 switchport mode E
 switchport trunk mode on
 switchport trunk allowed vsan 20
 no shutdown
exit
interface fc9/4
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc9/7
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc9/8
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc9/9
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/10
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/11
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/12
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/14
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/19
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/25
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/27
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/29
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/30
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/31
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/37
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/43
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc9/44
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/4
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc10/7
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc10/8
 switchport mode F
 switchport access vsan 50
 no shutdown
exit
interface fc10/10
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/12
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/14
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/16
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/17
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/19
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/29
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/30
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/33
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/35
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/37
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/43
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
interface fc10/44
 switchport mode F
 switchport access vsan 20
 no shutdown
exit
end
