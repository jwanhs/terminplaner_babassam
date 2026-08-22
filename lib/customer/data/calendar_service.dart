import 'package:add_2_calendar/add_2_calendar.dart';

import '../../core/brand.dart';
import 'models.dart';

/// Adds an [Appointment] to the user's native calendar via `add_2_calendar`.
/// On Android the package fires an `ACTION_INSERT` intent (no permission
/// needed). On iOS it uses EventKit and prompts the user for calendar access
/// the first time — the Info.plist must carry
/// `NSCalendarsFullAccessUsageDescription` (and `NSCalendarsUsageDescription`
/// for iOS < 17), otherwise the call silently fails.
class CalendarService {
  /// Defaults to this build's shop, so the calendar entry a customer keeps says
  /// the name over the door rather than the name of the reference deployment.
  CalendarService({BrandIdentity? brand}) : _brand = brand ?? brandLight;

  final BrandIdentity _brand;

  Future<bool> addAppointment(Appointment appt) {
    final event = Event(
      title: '${appt.serviceName} – ${_brand.businessName}',
      description: 'Termin bei ${_brand.businessName} (${_brand.tagline}) '
          'um ${appt.startLabel} Uhr.',
      location: _brand.businessName,
      // `add_2_calendar` reads these as *device-local* wall times, so the UTC
      // instants the API returns have to be converted — handing it a UTC
      // DateTime would file the appointment an offset's worth of hours out.
      // The device zone is the right one here: this is the customer's own
      // calendar, and they want the entry where they will be looking for it.
      startDate: appt.startAt.toLocal(),
      endDate: appt.endAt.toLocal(),
      iosParams: const IOSParams(reminder: Duration(hours: 1)),
    );
    return Add2Calendar.addEvent2Cal(event);
  }
}
