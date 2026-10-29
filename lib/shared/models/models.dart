class Facility {
  const Facility({
    required this.id,
    required this.name,
    required this.sportType,
    required this.isIndoor,
    required this.description,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.basePricePerHour,
    required this.rating,
    required this.imageUrl,
    required this.isActive,
    required this.archivedAt,
  });

  final int id;
  final String name;
  final String sportType;
  final bool isIndoor;
  final String description;
  final String locationName;
  final double latitude;
  final double longitude;
  final double basePricePerHour;
  final double rating;
  final String? imageUrl;
  final bool isActive;
  final DateTime? archivedAt;

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  factory Facility.fromJson(Map<String, dynamic> json) {
    final image = (json['image_url'] as String?)?.trim();
    return Facility(
      id: json['id'] as int,
      name: json['name'] as String,
      sportType: json['sport_type'] as String,
      isIndoor: json['is_indoor'] as bool,
      description: json['description'] as String? ?? '',
      locationName: json['location_name'] as String? ?? '-',
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      basePricePerHour: _toDouble(json['base_price_per_hour']),
      rating: _toDouble(json['rating'], fallback: 4.5),
      imageUrl: (image == null || image.isEmpty) ? null : image,
      isActive: json['is_active'] as bool? ?? true,
      archivedAt: (json['archived_at'] as String?) == null
          ? null
          : DateTime.tryParse(json['archived_at'] as String)?.toLocal(),
    );
  }
}

class TimeSlotItem {
  const TimeSlotItem({
    required this.id,
    required this.facility,
    required this.startAt,
    required this.endAt,
    required this.maxBookings,
    required this.currentBookings,
    required this.isOpen,
    required this.occupancyRate,
    required this.hasSpace,
  });

  final int id;
  final Facility facility;
  final DateTime startAt;
  final DateTime endAt;
  final int maxBookings;
  final int currentBookings;
  final bool isOpen;
  final double occupancyRate;
  final bool hasSpace;

  factory TimeSlotItem.fromJson(Map<String, dynamic> json) {
    return TimeSlotItem(
      id: json['id'] as int,
      facility: Facility.fromJson(json['facility'] as Map<String, dynamic>),
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: DateTime.parse(json['end_at'] as String).toLocal(),
      maxBookings: json['max_bookings'] as int,
      currentBookings: json['current_bookings'] as int,
      isOpen: json['is_open'] as bool,
      occupancyRate: (json['occupancy_rate'] as num).toDouble(),
      hasSpace: json['has_space'] as bool,
    );
  }
}

class BookingItem {
  const BookingItem({
    required this.id,
    required this.status,
    required this.paymentStatus,
    required this.finalPrice,
    required this.startAt,
    required this.endAt,
    required this.facilityName,
    required this.bookingSource,
    required this.chatbotSessionId,
    required this.couponCode,
    required this.couponDiscount,
  });

  final int id;
  final String status;
  final String paymentStatus;
  final double finalPrice;
  final DateTime startAt;
  final DateTime endAt;
  final String facilityName;
  final String bookingSource;
  final String chatbotSessionId;
  final String couponCode;
  final double couponDiscount;

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  factory BookingItem.fromJson(Map<String, dynamic> json) {
    final facility = json['facility'] as Map<String, dynamic>? ?? {};
    return BookingItem(
      id: json['id'] as int,
      status: json['status'] as String,
      paymentStatus: json['payment_status'] as String,
      finalPrice: _toDouble(json['final_price']),
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: DateTime.parse(json['end_at'] as String).toLocal(),
      facilityName: (facility['name'] as String?) ?? 'Unknown',
      bookingSource: (json['booking_source'] as String?) ?? 'manual',
      chatbotSessionId: (json['chatbot_session_id'] as String?) ?? '',
      couponCode: (json['coupon_code'] as String?) ?? '',
      couponDiscount: _toDouble(json['coupon_discount']),
    );
  }
}

class CouponItem {
  const CouponItem({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.discountPercent,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
    required this.isCurrentlyValid,
  });

  final int id;
  final String code;
  final String title;
  final String description;
  final double discountPercent;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;
  final bool isCurrentlyValid;

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  factory CouponItem.fromJson(Map<String, dynamic> json) {
    return CouponItem(
      id: json['id'] as int,
      code: (json['code'] as String? ?? '').trim().toUpperCase(),
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      discountPercent: _toDouble(json['discount_percent']),
      startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
      isActive: json['is_active'] as bool? ?? true,
      isCurrentlyValid: json['is_currently_valid'] as bool? ?? false,
    );
  }
}

class ChatSuggestion {
  const ChatSuggestion({
    required this.optionId,
    required this.facilityName,
    required this.startAt,
    required this.endAt,
    required this.durationHours,
    required this.finalPrice,
    required this.currency,
    required this.currentBookings,
    required this.maxBookings,
    required this.availableSpots,
    required this.isAvailable,
    required this.availabilityStatus,
    required this.basePrice,
    required this.weatherDiscount,
    required this.emptySlotDiscount,
    required this.rainMm,
    required this.isExactMatch,
  });

  final String optionId;
  final String facilityName;
  final String startAt;
  final String endAt;
  final double durationHours;
  final String finalPrice;
  final String currency;
  final int currentBookings;
  final int maxBookings;
  final int availableSpots;
  final bool isAvailable;
  final String availabilityStatus;
  final String basePrice;
  final String weatherDiscount;
  final String emptySlotDiscount;
  final double rainMm;
  final bool isExactMatch;

  factory ChatSuggestion.fromJson(Map<String, dynamic> json) {
    final startAt = (json['start_at'] ?? '').toString();
    final durationHours = (json['duration_hours'] as num).toDouble();
    var endAt = (json['end_at'] ?? '').toString();
    if (endAt.isEmpty) {
      final parsedStart = DateTime.tryParse(startAt);
      if (parsedStart != null) {
        endAt = parsedStart
            .add(Duration(minutes: (durationHours * 60).round()))
            .toIso8601String();
      }
    }

    return ChatSuggestion(
      optionId: json['option_id'] as String,
      facilityName: json['facility_name'] as String,
      startAt: startAt,
      endAt: endAt,
      durationHours: durationHours,
      finalPrice: json['final_price'] as String,
      currency: json['currency'] as String? ?? 'USD',
      currentBookings: (json['current_bookings'] as num?)?.toInt() ?? 0,
      maxBookings: (json['max_bookings'] as num?)?.toInt() ?? 0,
      availableSpots: (json['available_spots'] as num?)?.toInt() ?? 0,
      isAvailable: json['is_available'] as bool? ?? true,
      availabilityStatus: (json['availability_status'] as String? ?? '')
          .trim()
          .toLowerCase(),
      basePrice: (json['base_price'] ?? json['final_price'] ?? '0').toString(),
      weatherDiscount: (json['weather_discount'] ?? '0.00').toString(),
      emptySlotDiscount: (json['empty_slot_discount'] ?? '0.00').toString(),
      rainMm: (json['rain_mm'] as num?)?.toDouble() ?? 0,
      isExactMatch: json['is_exact_match'] as bool? ?? false,
    );
  }
}

class ChatSessionItem {
  const ChatSessionItem({
    required this.sessionId,
    required this.title,
    required this.createdAt,
    required this.lastMessageAt,
    required this.messageCount,
  });

  final String sessionId;
  final String title;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final int messageCount;

  factory ChatSessionItem.fromJson(Map<String, dynamic> json) {
    return ChatSessionItem(
      sessionId: json['session_id'] as String,
      title: (json['title'] as String?) ?? 'AI Booking Session',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      lastMessageAt: DateTime.parse(
        json['last_message_at'] as String,
      ).toLocal(),
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class DashboardSportAvailability {
  const DashboardSportAvailability({
    required this.sportType,
    required this.availableSlots,
    required this.nextStartAt,
  });

  final String sportType;
  final int availableSlots;
  final DateTime? nextStartAt;

  factory DashboardSportAvailability.fromJson(Map<String, dynamic> json) {
    return DashboardSportAvailability(
      sportType: (json['sport_type'] as String? ?? 'unknown').toLowerCase(),
      availableSlots: (json['available_slots'] as num?)?.toInt() ?? 0,
      nextStartAt: (json['next_start_at'] as String?) == null
          ? null
          : DateTime.parse(json['next_start_at'] as String).toLocal(),
    );
  }
}

class DashboardUpcomingSlot {
  const DashboardUpcomingSlot({
    required this.slotId,
    required this.facilityId,
    required this.facilityName,
    required this.sportType,
    required this.isIndoor,
    required this.startAt,
    required this.endAt,
    required this.basePricePerHour,
    required this.currentBookings,
    required this.maxBookings,
  });

  final int slotId;
  final int facilityId;
  final String facilityName;
  final String sportType;
  final bool isIndoor;
  final DateTime startAt;
  final DateTime endAt;
  final double basePricePerHour;
  final int currentBookings;
  final int maxBookings;

  factory DashboardUpcomingSlot.fromJson(Map<String, dynamic> json) {
    return DashboardUpcomingSlot(
      slotId: (json['slot_id'] as num).toInt(),
      facilityId: (json['facility_id'] as num).toInt(),
      facilityName: json['facility_name'] as String? ?? '-',
      sportType: (json['sport_type'] as String? ?? 'unknown').toLowerCase(),
      isIndoor: json['is_indoor'] as bool? ?? false,
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: DateTime.parse(json['end_at'] as String).toLocal(),
      basePricePerHour: (json['base_price_per_hour'] as num).toDouble(),
      currentBookings: (json['current_bookings'] as num).toInt(),
      maxBookings: (json['max_bookings'] as num).toInt(),
    );
  }
}

class DashboardSummary {
  const DashboardSummary({
    required this.confirmedCount,
    required this.pendingCount,
    required this.totalSpent,
    required this.sportAvailability,
    required this.upcomingSlots,
  });

  final int confirmedCount;
  final int pendingCount;
  final double totalSpent;
  final List<DashboardSportAvailability> sportAvailability;
  final List<DashboardUpcomingSlot> upcomingSlots;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final sportRows = (json['sport_availability'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DashboardSportAvailability.fromJson)
        .toList();

    final upcomingRows = (json['upcoming_slots'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DashboardUpcomingSlot.fromJson)
        .toList();

    return DashboardSummary(
      confirmedCount: (json['confirmed_count'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0,
      sportAvailability: sportRows,
      upcomingSlots: upcomingRows,
    );
  }
}

class OwnerAnalytics {
  const OwnerAnalytics({
    required this.totalBookings,
    required this.confirmedBookings,
    required this.pendingBookings,
    required this.cancelledBookings,
    required this.revenue,
    required this.refunds,
    required this.netRevenue,
    required this.cancellationRate,
  });

  final int totalBookings;
  final int confirmedBookings;
  final int pendingBookings;
  final int cancelledBookings;
  final double revenue;
  final double refunds;
  final double netRevenue;
  final double cancellationRate;

  factory OwnerAnalytics.fromJson(Map<String, dynamic> json) {
    double number(dynamic value) => double.tryParse(value.toString()) ?? 0;
    return OwnerAnalytics(
      totalBookings: (json['total_bookings'] as num?)?.toInt() ?? 0,
      confirmedBookings: (json['confirmed_bookings'] as num?)?.toInt() ?? 0,
      pendingBookings: (json['pending_bookings'] as num?)?.toInt() ?? 0,
      cancelledBookings: (json['cancelled_bookings'] as num?)?.toInt() ?? 0,
      revenue: number(json['revenue']),
      refunds: number(json['refunds']),
      netRevenue: number(json['net_revenue']),
      cancellationRate: number(json['cancellation_rate']),
    );
  }
}

class LiveSlotAvailability {
  const LiveSlotAvailability({
    required this.slotId,
    required this.facilityId,
    required this.facilityName,
    required this.sportType,
    required this.startAt,
    required this.endAt,
    required this.currentBookings,
    required this.maxBookings,
    required this.isOpen,
    required this.isAvailable,
    required this.basePricePerHour,
    required this.isIndoor,
    required this.locationName,
    required this.slotVersion,
    required this.reservationHoldUntil,
    required this.bookedByMe,
    required this.availabilityStatus,
  });

  final String slotId;
  final String facilityId;
  final String facilityName;
  final String sportType;
  final DateTime startAt;
  final DateTime endAt;
  final int currentBookings;
  final int maxBookings;
  final bool isOpen;
  final bool isAvailable;
  final double basePricePerHour;
  final bool isIndoor;
  final String locationName;
  final int slotVersion;
  final DateTime? reservationHoldUntil;
  final bool bookedByMe;
  final String availabilityStatus;

  factory LiveSlotAvailability.fromJson(Map<String, dynamic> json) {
    return LiveSlotAvailability(
      slotId: (json['slot_id'] ?? '').toString(),
      facilityId: (json['facility_id'] ?? '').toString(),
      facilityName: json['facility_name'] as String? ?? '-',
      sportType: (json['sport_type'] as String? ?? 'unknown').toLowerCase(),
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: DateTime.parse(json['end_at'] as String).toLocal(),
      currentBookings: (json['current_bookings'] as num?)?.toInt() ?? 0,
      maxBookings: (json['max_bookings'] as num?)?.toInt() ?? 0,
      isOpen: json['is_open'] as bool? ?? false,
      isAvailable: json['is_available'] as bool? ?? false,
      basePricePerHour: (json['base_price_per_hour'] as num?)?.toDouble() ?? 0,
      isIndoor: json['is_indoor'] as bool? ?? false,
      locationName: json['location_name'] as String? ?? '-',
      slotVersion: (json['slot_version'] as num?)?.toInt() ?? 1,
      reservationHoldUntil: (json['reservation_hold_until'] as String?) == null
          ? null
          : DateTime.tryParse(
              json['reservation_hold_until'] as String,
            )?.toLocal(),
      bookedByMe: json['booked_by_me'] as bool? ?? false,
      availabilityStatus: ((json['availability_status'] as String?) ?? '')
          .trim()
          .toLowerCase(),
    );
  }
}
