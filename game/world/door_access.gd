extends RefCounted
## Ordinary door refusals from event_rules.c at the original starting friendship.
## Each row is [opening hour, closing hour, optional villager, required area].
const ACCESS := {
	6: [10,18,"popuri",128],
	8: [10,18,"barley",136],
	11: [10,18,"saibara",156],
	13: [9,18,"manna",144],
	19: [10,18,"anna",164],
	21: [9,18,"mary",160],
	22: [9,18,"mary",160],
	23: [10,18,"mayor_thomas",176],
	24: [10,18,"ellen",172],
	25: [9,18,"jeff",180],
	27: [9,18,"doctor",188],
	31: [10,18],
	33: [9,18],
	34: [8,21],
	42: [10,18,"gotz",212],
}
const POULTRY_SUNDAY := [10,18,"rick",128]
const EVENING_HOURS := [18,24]
const INN_FALL_5 := [11,17,"doug",204]
const PRIVATE_ROOMS := [7,10,12,16,17,20,26,28,29,30,37,40,41,48]
# The first 14 rows of clock_date_table. The clock stores the day zero-based.
const CLOSED_DATES := [[0,7,17,21],[0,6,11,19,23],[2,8,20],[9,23]]


static func is_locked(event_id: int, minute: int, season: int, day: int, weekday: int,
		scheduled_areas: Dictionary) -> bool:
	if event_id in PRIVATE_ROOMS:
		return true
	if not ACCESS.has(event_id):
		return false
	var hours: Array = ACCESS[event_id]
	if day in CLOSED_DATES[season]:
		# The source day-item exceptions allow these rules through on these dates.
		if (event_id==34 and season==0 and day==0) or (event_id==31 and season==2 and day==2):
			hours = EVENING_HOURS
		else:
			return true
	elif event_id==34 and season==2 and day==4:
		hours = INN_FALL_5
	elif event_id==6 and weekday==0:
		hours = POULTRY_SUNDAY
	if minute < int(hours[0])*60 or minute >= int(hours[1])*60:
		return true
	return hours.size()>2 and int(scheduled_areas.get(hours[2],-1)) != int(hours[3])
