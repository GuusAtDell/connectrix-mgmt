configure terminal
device-alias database
 device-alias name DEDUSAN200_CT0FC8 pwwn 52:4a:93:7b:d5:ed:c2:08
 device-alias name DEDUSAN200_CT1FC8 pwwn 52:4a:93:7b:d5:ed:c2:18
 device-alias name DELESAN200_CT0FC8 pwwn 52:4a:93:79:cc:ae:93:08
 device-alias name DELESAN200_CT1FC8 pwwn 52:4a:93:79:cc:ae:93:18
 device-alias name deea149472_A1 pwwn 10:00:00:10:9b:9b:7b:a8
 device-alias name deea149474_A1 pwwn 10:00:00:10:9b:9e:12:c0
 device-alias name deea153027_A1 pwwn 10:00:70:b7:e4:2b:78:48
 device-alias name deea153029_A1 pwwn 10:00:70:b7:e4:2a:0a:ba
 device-alias name deeb149473_A1 pwwn 10:00:00:10:9b:9b:76:6f
 device-alias name deeb149475_A1 pwwn 10:00:00:10:9b:9b:76:30
 device-alias name deeb153028_A1 pwwn 10:00:70:b7:e4:2b:77:e1
 device-alias name deeb153030_A1 pwwn 10:00:70:b7:e4:2a:09:cc
exit
device-alias commit
end
configure terminal
zone name Z_INTE_ESX_DEDUSAN200 vsan 100
 member device-alias DEDUSAN200_CT0FC8
 member device-alias DEDUSAN200_CT1FC8
 member device-alias deea153027_A1
 member device-alias deea153029_A1
 member device-alias deeb153028_A1
 member device-alias deeb153030_A1
exit
zone name Z_INTE_ESX_DELESAN200 vsan 100
 member device-alias DELESAN200_CT0FC8
 member device-alias DELESAN200_CT1FC8
 member device-alias deea153027_A1
 member device-alias deea153029_A1
 member device-alias deeb153028_A1
 member device-alias deeb153030_A1
exit
zone name Z_KUND_ESX_DEDUSAN200 vsan 100
 member device-alias DEDUSAN200_CT0FC8
 member device-alias DEDUSAN200_CT1FC8
 member device-alias deea149472_A1
 member device-alias deea149474_A1
 member device-alias deeb149473_A1
 member device-alias deeb149475_A1
exit
zone name Z_KUND_ESX_DELESAN200 vsan 100
 member device-alias DELESAN200_CT0FC8
 member device-alias DELESAN200_CT1FC8
 member device-alias deea149472_A1
 member device-alias deea149474_A1
 member device-alias deeb149473_A1
 member device-alias deeb149475_A1
exit
end
configure terminal
zoneset name DMZ_Fabric_1 vsan 100
 member Z_INTE_ESX_DEDUSAN200
 member Z_INTE_ESX_DELESAN200
 member Z_KUND_ESX_DEDUSAN200
 member Z_KUND_ESX_DELESAN200
exit
end
zone commit vsan 100
configure terminal
zoneset activate name DMZ_Fabric_1 vsan 100
end
copy running-config startup-config
show zoneset active vsan 100
show device-alias database
show zone vsan 100
show zone status vsan 100
