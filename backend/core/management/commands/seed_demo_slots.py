from datetime import datetime, timedelta
from decimal import Decimal
import random

from django.core.management.base import BaseCommand
from django.utils import timezone

from core.models import Facility, SportType, TimeSlot


class Command(BaseCommand):
    help = 'Seed demo facilities and timeslots for all sports.'

    def add_arguments(self, parser):
        parser.add_argument('--days', type=int, default=3, help='Number of future days to generate')

    def handle(self, *args, **options):
        days = max(1, min(options['days'], 14))

        clubs_by_sport = {
            SportType.FOOTBALL: [
                ('Elite Football Arena - Pitch 01', 'Downtown Sports Complex', Decimal('50.00')),
                ('Riverfront Football Hub - Pitch 02', 'Riverside District', Decimal('46.00')),
                ('City Strikers Ground - Pitch 03', 'North Avenue', Decimal('48.00')),
                ('Greenfield United Club - Pitch 04', 'Boeung Keng Kang', Decimal('47.00')),
                ('Thunder Kick Football Club - Pitch 05', 'Tuol Kork', Decimal('49.00')),
                ('Victory Goal Arena - Pitch 06', 'Mean Chey', Decimal('45.00')),
            ],
            SportType.BILLIARD: [
                ('Royal Cue Club - Table 01', 'BKK1', Decimal('18.00')),
                ('Midnight Billiard Lounge - Table 02', 'Toul Kork', Decimal('17.00')),
                ('Precision Cue House - Table 03', 'Sangkat Boeung Keng Kang', Decimal('16.00')),
                ('Corner Pocket Billiard Club - Table 04', 'Sangkat Tonle Bassac', Decimal('19.00')),
                ('Golden Break Billiard Club - Table 05', 'Chbar Ampov', Decimal('18.50')),
                ('Blue Chalk Billiard Lounge - Table 06', 'Daun Penh', Decimal('17.50')),
            ],
            SportType.PICKLEBALL: [
                ('Ace Pickle Dome', 'Olympic Area', Decimal('24.00')),
                ('Smash Pickle Club', 'Sen Sok', Decimal('22.00')),
                ('SpinServe Pickle Park', 'Chroy Changvar', Decimal('23.00')),
                ('Rally Point Pickle Club', 'Phnom Penh Thmey', Decimal('23.00')),
                ('Drop Shot Pickle Club', 'Russey Keo', Decimal('22.50')),
                ('Paddle Pulse Arena', 'Dangkor', Decimal('24.50')),
            ],
            SportType.VOLLEYBALL: [
                ('Skyline Volleyball Court', 'Central Park Zone', Decimal('28.00')),
                ('Net Masters Arena', 'Riverside Drive', Decimal('26.00')),
                ('High Jump Volleyball Club', 'Russey Keo', Decimal('27.00')),
                ('Power Serve Volleyball Hub', 'Dangkor', Decimal('29.00')),
                ('Beach Spike Volleyball Club', 'Chroy Changvar', Decimal('27.50')),
                ('Sky Serve Volleyball Hall', 'Tuol Kork', Decimal('28.50')),
            ],
            SportType.BASKETBALL: [
                ('Downtown Hoops Center', 'Monivong Blvd', Decimal('30.00')),
                ('Rim City Court', 'Tuol Tom Poung', Decimal('32.00')),
                ('Full Court Club', 'Mean Chey', Decimal('29.00')),
                ('Sky Dunk Basketball Club', 'Chamkarmon', Decimal('31.00')),
                ('Street Shot Basketball Club', '7 Makara', Decimal('30.50')),
                ('Fast Break Arena', 'Boeung Trabek', Decimal('31.50')),
            ],
            SportType.FUTSAL: [
                ('Pro Futsal Dome', '7 Makara', Decimal('35.00')),
                ('Falcon Futsal Club', 'Chbar Ampov', Decimal('33.00')),
                ('Urban Kick Futsal Arena', 'Prek Pnov', Decimal('34.00')),
                ('Night Lights Futsal Club', 'Por Senchey', Decimal('36.00')),
                ('Street Five Futsal Club', 'Russey Keo', Decimal('34.50')),
                ('Urban Pulse Futsal Hub', 'Sen Sok', Decimal('35.50')),
            ],
            SportType.TENNIS: [
                ('Grand Slam Tennis Club', 'Riverside Drive', Decimal('40.00')),
                ('Topspin Tennis Garden', 'Boeung Trabek', Decimal('38.00')),
                ('Courtline Tennis Hub', 'Koh Pich', Decimal('42.00')),
                ('Baseline Tennis Club', 'Sen Sok', Decimal('39.00')),
                ('Spin Ace Tennis Club', 'Chamkarmon', Decimal('41.00')),
                ('Center Court Tennis Arena', 'Tuol Kork', Decimal('40.50')),
            ],
            SportType.BADMINTON: [
                ('FeatherPro Badminton Hall', 'Sen Sok', Decimal('20.00')),
                ('Shuttle Prime Arena', 'Chamkarmon', Decimal('22.00')),
                ('Aero Badminton Club', 'Tuol Kork', Decimal('21.00')),
                ('Rapid Shuttle Club', 'Russey Keo', Decimal('22.00')),
                ('Clear Shot Badminton Club', 'BKK2', Decimal('21.50')),
                ('Smash Point Badminton Hub', 'Dangkor', Decimal('22.50')),
            ],
        }

        created_facilities = 0
        created_slots = 0

        for sport, clubs in clubs_by_sport.items():
            for club_index, (club_name, location_name, base_price) in enumerate(clubs):
                is_indoor = sport in [SportType.BILLIARD, SportType.BADMINTON, SportType.PICKLEBALL]
                latitude = 11.5564 + (club_index * 0.008)
                longitude = 104.9282 + (club_index * 0.006)

                facility, was_created = Facility.objects.get_or_create(
                    name=club_name,
                    defaults={
                        'sport_type': sport,
                        'is_indoor': is_indoor,
                        'description': f'{sport.title()} venue with smart live-slot booking and chatbot support.',
                        'location_name': location_name,
                        'latitude': latitude,
                        'longitude': longitude,
                        'base_price_per_hour': base_price,
                        'rating': Decimal(str(round(4.3 + (club_index * 0.2), 1))),
                        'is_active': True,
                    },
                )

                if was_created:
                    created_facilities += 1

                max_bookings_for_sport = 1 if sport == SportType.BILLIARD else 4

                for day_offset in range(1, days + 1):
                    day = timezone.localdate() + timedelta(days=day_offset)
                    for hour in range(8, 22, 2):
                        start_naive = datetime.combine(day, datetime.min.time()).replace(hour=hour)
                        end_naive = start_naive + timedelta(hours=2)
                        start_at = timezone.make_aware(start_naive)
                        end_at = timezone.make_aware(end_naive)

                        deterministic_seed = f'{facility.id}-{day_offset}-{hour}'
                        random.seed(deterministic_seed)
                        current_bookings = random.randint(0, max_bookings_for_sport)
                        is_open = random.random() > 0.08

                        slot, slot_created = TimeSlot.objects.get_or_create(
                            facility=facility,
                            start_at=start_at,
                            end_at=end_at,
                            defaults={
                                'max_bookings': max_bookings_for_sport,
                                'current_bookings': current_bookings,
                                'is_open': is_open,
                            },
                        )

                        if slot_created:
                            created_slots += 1
                        else:
                            slot.max_bookings = max_bookings_for_sport
                            slot.current_bookings = min(current_bookings, max_bookings_for_sport)
                            slot.is_open = is_open
                            slot.save(
                                update_fields=[
                                    'max_bookings',
                                    'current_bookings',
                                    'is_open',
                                    'availability_state',
                                    'availability_updated_at',
                                    'updated_at',
                                ]
                            )

        self.stdout.write(
            self.style.SUCCESS(
                f'Seed complete. Facilities created: {created_facilities}, slots created: {created_slots}'
            )
        )
