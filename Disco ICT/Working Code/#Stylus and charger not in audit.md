#Stylus and charger not in audit
DeviceSerialNumber: R9134VFQ
UserId: CURRIC\WIL0142
SourceUrl: http://disco:9292/Device/Show/R9134VFQ
Type: HNWar
SubTypes: HNWar_Other
SubTypes: HNWar_PowerAdapter
SubTypes: HNWar_PowerCord
DeviceHeld: False
_DeviceHeld: false
Comments: Charger and Stylus not present during audit, and not brought in since. Stylus had an unpaid amount from 2023 audit as well


#

SubTypes: HNWar_Bag # Bag Non-Warranty
SubTypes: HNWar_Other # Other Non-Warranty This would be Stylus, Insurance etc
SubTypes: HNWar_PowerAdapter #Non-Warranty Power Adapter In Non-Warranty this is paired with Power Cord
SubTypes: HNWar_PowerCord #Non-Warranty Power Cord - In Non-Warranty this is paired with Power Adapter

#Document Generation
http://disco:9292/API/DocumentTemplate/Generate/Repair%20Quote?TargetId=10217

#Add SubTypes
http://disco:9292/API/Job/UpdateSubTypes/10226?redirect=True
SubTypes: HNWar_Bag
SubTypes: HNWar_Other
AddComponents: true

