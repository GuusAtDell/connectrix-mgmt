configure terminal
device-alias database
 device-alias name deea149494_A1 pwwn 10:00:00:10:9b:a5:15:0c
 device-alias name deea149495_A1 pwwn 10:00:00:10:9b:a5:13:0f
 device-alias name deea149496_A1 pwwn 10:00:00:10:9b:a5:15:90
 device-alias name deea149497_A1 pwwn 10:00:00:10:9b:a5:15:57
 device-alias name deea149498_A1 pwwn 10:00:00:10:9b:a5:15:bd
 device-alias name deea149499_A1 pwwn 10:00:00:10:9b:a5:6b:b7
 device-alias name deea149500_A1 pwwn 10:00:00:10:9b:a5:ef:51
 device-alias name deea152189_A1 pwwn 10:00:70:b7:e4:07:7d:f9
 device-alias name deea152190_A1 pwwn 10:00:70:b7:e4:07:7d:a5
 device-alias name deea152191_A1 pwwn 10:00:70:b7:e4:07:7b:54
 device-alias name deea152418_A1 pwwn 10:00:00:10:9b:e1:0d:7e
 device-alias name deea152419_A1 pwwn 10:00:00:10:9b:e1:0d:ba
 device-alias name deea152420_A1 pwwn 10:00:00:10:9b:e1:46:ed
 device-alias name deea152421_A1 pwwn 10:00:00:10:9b:e1:0d:f0
 device-alias name deea152422_A1 pwwn 10:00:00:10:9b:e1:48:09
 device-alias name deea152423_A1 pwwn 10:00:00:10:9b:e1:47:3c
 device-alias name deea152424_A1 pwwn 10:00:00:10:9b:e0:fe:03
 device-alias name deea152425_A1 pwwn 10:00:00:10:9b:e1:b0:33
 device-alias name deea152426_A1 pwwn 10:00:00:10:9b:e1:af:f3
 device-alias name deea152427_A1 pwwn 10:00:00:10:9b:e7:30:c3
 device-alias name deea152428_A1 pwwn 10:00:00:10:9b:e7:2f:5d
 device-alias name deea152429_A1 pwwn 10:00:00:10:9b:e7:30:bd
 device-alias name deea152430_A1 pwwn 10:00:00:10:9b:e1:b0:15
 device-alias name deea152431_A1 pwwn 10:00:00:10:9b:e7:30:39
 device-alias name deea152432_A1 pwwn 10:00:00:10:9b:e1:af:de
 device-alias name deea152433_A1 pwwn 10:00:00:10:9b:e1:ae:12
 device-alias name deea152434_A1 pwwn 10:00:00:10:9b:e1:ae:99
 device-alias name deea153000_A1 pwwn 10:00:70:b7:e4:32:36:c9
 device-alias name deea153001_A1 pwwn 10:00:70:b7:e4:32:36:18
 device-alias name deea153002_A1 pwwn 10:00:70:b7:e4:32:36:c6
 device-alias name deea153003_A1 pwwn 10:00:70:b7:e4:32:36:a5
 device-alias name deea153004_A1 pwwn 10:00:70:b7:e4:32:34:45
 device-alias name deea153005_A1 pwwn 10:00:70:b7:e4:32:36:a8
 device-alias name deea153006_A1 pwwn 10:00:70:b7:e4:33:1e:db
 device-alias name deeqxsan500_CT0_FC0 pwwn 52:4a:93:78:9f:e0:1c:00
 device-alias name deeqxsan500_CT0_FC2 pwwn 52:4a:93:78:9f:e0:1c:02
 device-alias name deeqxsan500_CT1_FC0 pwwn 52:4a:93:78:9f:e0:1c:10
 device-alias name deeqxsan500_CT1_FC2 pwwn 52:4a:93:78:9f:e0:1c:12
 device-alias name dex20151790_CT0_FC4 pwwn 52:4a:93:78:0e:9b:61:00
 device-alias name dex20151790_CT0_FC6 pwwn 52:4a:93:78:0e:9b:61:02
 device-alias name dex20151790_CT1_FC4 pwwn 52:4a:93:78:0e:9b:61:10
 device-alias name dex20151790_CT1_FC6 pwwn 52:4a:93:78:0e:9b:61:12
exit
device-alias commit
end
configure terminal
zone name Z_VDI-DEEQXSAN500_A vsan 50
 member device-alias deeqxsan500_CT0_FC0
 member device-alias deeqxsan500_CT0_FC2
 member device-alias deeqxsan500_CT1_FC0
 member device-alias deeqxsan500_CT1_FC2
 member device-alias deea152418_A1
 member device-alias deea152419_A1
 member device-alias deea152420_A1
 member device-alias deea152421_A1
 member device-alias deea152422_A1
 member device-alias deea152423_A1
 member device-alias deea152424_A1
 member device-alias deea152425_A1
 member device-alias deea152426_A1
 member device-alias deea152427_A1
 member device-alias deea152428_A1
 member device-alias deea152429_A1
 member device-alias deea152430_A1
 member device-alias deea152431_A1
 member device-alias deea152432_A1
 member device-alias deea152433_A1
 member device-alias deea152434_A1
exit
zone name Z_VDI-DEX20151790_A vsan 50
 member device-alias dex20151790_CT0_FC4
 member device-alias dex20151790_CT0_FC6
 member device-alias dex20151790_CT1_FC4
 member device-alias dex20151790_CT1_FC6
 member device-alias deea149494_A1
 member device-alias deea149495_A1
 member device-alias deea149496_A1
 member device-alias deea149497_A1
 member device-alias deea149498_A1
 member device-alias deea149499_A1
 member device-alias deea149500_A1
 member device-alias deea152189_A1
 member device-alias deea152190_A1
 member device-alias deea152191_A1
 member device-alias deea153000_A1
 member device-alias deea153001_A1
 member device-alias deea153002_A1
 member device-alias deea153003_A1
 member device-alias deea153004_A1
 member device-alias deea153005_A1
 member device-alias deea153006_A1
exit
end
configure terminal
zoneset name ZS_001_EQX_VDI_A vsan 50
 member Z_VDI-DEEQXSAN500_A
 member Z_VDI-DEX20151790_A
exit
end
zone commit vsan 50
configure terminal
zoneset activate name ZS_001_EQX_VDI_A vsan 50
end
copy running-config startup-config
show zoneset active vsan 50
show device-alias database
show zone vsan 50
show zone status vsan 50
