# E-Booking Sport System

A Flutter mobile application for booking sports facilities integrated with a Django backend, Supabase database, and Groq AI API.

## Project Structure

```
my_project/
├── lib/
│   ├── app/               # Application shell and global theme
│   ├── features/          # Feature-owned screens, state, and data access
│   └── shared/            # Cross-feature models, platform, network, and UI helpers
├── backend/
│   ├── config/            # Django project configuration
│   ├── core/              # Existing persistence app and compatibility boundary
│   ├── features/          # Feature-owned API routing and utilities
│   └── global_utils/      # Reusable backend helpers shared across features
├── android/               # Android native configuration
├── ios/                   # iOS native configuration
└── web/                   # Web platform configuration
```

The frontend follows a feature-first structure. Code used by one feature stays
under `lib/features/<feature>`, while reusable infrastructure belongs under
`lib/shared`. The backend keeps the existing `core` Django app as the model and
migration boundary, while its HTTP routes are organized under
`backend/features/<feature>` without changing API paths or database table names.
Feature-local reusable functions live under each feature's `utils` directory;
cross-feature helpers live under `backend/global_utils`.

## Prerequisites

- **Flutter SDK** (v3.0+)
- **Python 3.9+** (for backend)
- **Git**
- **Supabase Account** (database)
- **Groq API Key** (AI integration)
- **Django** (backend framework)

## 🔑 Setting Up Credentials

### ⚠️ Important: Environment Variables

This project uses API keys and credentials that should **NEVER** be committed to version control. We use environment files to manage these securely.

### Backend Credentials (Django)

**File Location:** `backend/.env`

```bash
# Navigate to the backend folder
cd backend

# Copy the example environment file
cp .env.example .env

# Open .env and add your credentials
```

**Edit `backend/.env` and add your credentials:**

```env
DEBUG=True
SECRET_KEY=your_django_secret_key_here
ALLOWED_HOSTS=127.0.0.1,localhost

SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your_supabase_service_role_key_here
SUPABASE_BOOKING_TABLE=core_booking
SUPABASE_TIMESLOT_TABLE=core_timeslot

GROQ_API_KEY=your_groq_api_key_here
```

### Flutter Frontend Credentials

**File Location:** `my_project/.env` (in root directory)

The Flutter app connects to Supabase using the anon key (safe to share):

```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_supabase_anon_key_here
BACKEND_URL=http://127.0.0.1:8000
```

### How to Get Your Credentials

#### 1. **Supabase Setup**
   - Go to [supabase.com](https://supabase.com)
   - Create a new project
   - Navigate to **Settings → API**
   - Copy the **Project URL** → `SUPABASE_URL`
   - Copy the **Service Role Secret Key** → `SUPABASE_SERVICE_ROLE_KEY` (backend only)
   - Copy the **Anon Public Key** → `SUPABASE_ANON_KEY` (frontend)

#### 2. **Groq API Key**
   - Go to [console.groq.com](https://console.groq.com)
   - Sign up / Log in
   - Navigate to **API Keys**
   - Create a new API key
   - Copy the key → `GROQ_API_KEY`

#### 3. **Django Secret Key**
   - Generate using Python:
     ```bash
     python -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())'
     ```
   - Copy the output → `SECRET_KEY`

## 🚀 Getting Started

### Backend Setup

```bash
cd backend

# Install dependencies
pip install -r requirements.txt

# Create .env file with your credentials
cp .env.example .env
# Edit .env with your API keys

# Run migrations
python manage.py migrate

# Start the development server
python manage.py runserver
```

The backend will be available at: `http://127.0.0.1:8000`

### Flutter Frontend Setup

```bash
# Install Flutter dependencies
flutter pub get

# Create .env file in root directory (if using flutter_dotenv)
# Add your Supabase credentials

# Run the app
flutter run

# Or run on specific platform
flutter run -d chrome        # Web
flutter run -d android      # Android emulator
flutter run -d ios          # iOS simulator
```

### Docker

The backend uses a small Python Alpine image and the Flutter web app uses a
multi-stage build with an Nginx Alpine runtime image. The Flutter SDK remains
in the builder image because the official Flutter toolchain is not distributed
as an Alpine image.

Create `backend/.env` from `backend/.env.example`, then build and start both
services:

```bash
docker compose up --build
```

The Django API is available at `http://localhost:8000` and the Flutter web app
at `http://localhost:8080`. Frontend build arguments can be supplied through
the root environment, for example `BACKEND_URL`, `SUPABASE_URL`, and
`SUPABASE_ANON_KEY`.

The reusable backend helpers are grouped under
`backend/global_utils/` by responsibility. `view_helpers.py` remains a
backward-compatible export module for existing feature imports; new helpers
should be added to the focused module that owns the behavior.

## ✅ Verify Setup

### Check Backend Connection
```bash
cd backend
curl http://127.0.0.1:8000/api/bookings/
```

### Check Flutter Connection
```bash
# This will show if the app can connect to backend and Supabase
flutter run
```

## �️ Database Models

The application uses Django ORM with the following models. These will be automatically created when you run migrations.

### Entity Relationship Diagram

```
┌─────────────┐
│  Facility   │
├─────────────┤
│ id (PK)     │
│ name        │
│ sport_type  │
│ location    │
│ price/hour  │
└──────┬──────┘
       │ 1:N
       │
       ▼
┌─────────────────┐        ┌──────────────┐
│   TimeSlot      │◄───┐   │   Booking    │
├─────────────────┤    │   ├──────────────┤
│ id (PK)         │    │   │ id (PK)      │
│ facility_id (FK)│    │   │ user_id      │
│ start_at        │    │   │ facility_id  │
│ end_at          │    │   │ time_slot_id │
│ max_bookings    │    │   │ start_at     │
│ current_bookings│    │   │ end_at       │
│ is_open         │    └───│ status       │
└─────────────────┘    N:1 │ payment_status
                            │ base_price   │
                            │ final_price  │
                            └──────────────┘
```

### Detailed Model Specifications

#### 1. **Facility Model**
Represents a sports facility available for booking.

| Field | Type | Description |
|-------|------|-------------|
| `id` | Primary Key | Auto-generated |
| `name` | CharField(120) | Name of the facility |
| `sport_type` | CharField(32) | Type of sport (football, basketball, etc.) |
| `is_indoor` | Boolean | Whether facility is indoor or outdoor |
| `description` | TextField | Detailed description |
| `location_name` | CharField(255) | Address/location name |
| `latitude` | Float | GPS latitude coordinate |
| `longitude` | Float | GPS longitude coordinate |
| `base_price_per_hour` | Decimal | Hourly rate (max_digits=10, decimal_places=2) |
| `owner_user_id` | UUID | Owner's user ID (from Supabase auth) |
| `is_active` | Boolean | Active/inactive status |
| `created_at` | DateTime | Auto-set on creation |
| `updated_at` | DateTime | Auto-updated on changes |

**Sport Types Available:**
- Football
- Billiard
- Pickleball
- Volleyball
- Basketball
- Futsal
- Tennis
- Badminton

#### 2. **TimeSlot Model**
Represents available time slots for a facility.

| Field | Type | Description |
|-------|------|-------------|
| `id` | Primary Key | Auto-generated |
| `facility_id` | ForeignKey | Links to Facility |
| `start_at` | DateTime | Slot start time |
| `end_at` | DateTime | Slot end time |
| `max_bookings` | PositiveInt | Maximum concurrent bookings |
| `current_bookings` | PositiveInt | Current booking count |
| `is_open` | Boolean | Slot availability status |
| `created_at` | DateTime | Auto-set on creation |
| `updated_at` | DateTime | Auto-updated on changes |

**Key Properties:**
- `occupancy_rate`: Calculated as `current_bookings / max_bookings`
- `has_space`: Returns `True` if slot is open and not full

#### 3. **Booking Model**
Represents a user's reservation for a facility time slot.

| Field | Type | Description |
|-------|------|-------------|
| `id` | Primary Key | Auto-generated |
| `user_id` | UUID | Supabase user ID |
| `facility_id` | ForeignKey | Links to Facility |
| `time_slot_id` | ForeignKey | Links to TimeSlot |
| `start_at` | DateTime | Booking start time |
| `end_at` | DateTime | Booking end time |
| `duration_hours` | Decimal | Calculated duration (max_digits=4, decimal_places=2) |
| `status` | CharField(20) | Booking status (see below) |
| `payment_status` | CharField(20) | Payment status (see below) |
| `base_price` | Decimal | Price before discounts |
| `weather_discount` | Decimal | Discount applied (rain > 5mm on outdoor) |
| `empty_slot_discount` | Decimal | Discount for low occupancy (< 30%) |
| `final_price` | Decimal | Final price after all discounts |
| `weather_rain_mm` | Float | Rainfall recorded at booking time |
| `notes` | TextField | Additional notes |
| `created_at` | DateTime | Auto-set on creation |
| `updated_at` | DateTime | Auto-updated on changes |

**Booking Status Options:**
- `PENDING` - Awaiting confirmation
- `CONFIRMED` - Booking confirmed
- `CANCELLED` - Booking cancelled
- `RESCHEDULED` - Booking rescheduled

**Payment Status Options:**
- `MOCK_PENDING` - Payment pending (mock system)
- `MOCK_PAID` - Payment completed (mock system)
- `MOCK_FAILED` - Payment failed (mock system)

### Dynamic Pricing Algorithm

Bookings use a dynamic pricing system with the following logic:

```python
# Base calculation
base_price = base_price_per_hour × duration_hours

# Weather Discount (Outdoor only)
if not is_indoor and rain_mm > 5.0:
    weather_discount = base_price × 10%
    
# Empty Slot Discount (Low occupancy)
if occupancy_rate < 30%:
    empty_slot_discount = base_price × 15%
    
# Final Price
final_price = base_price - weather_discount - empty_slot_discount
(minimum: $0.00)
```

### Setting Up the Database

#### 1. **Run Migrations**
```bash
cd backend
python manage.py migrate
```

This creates all tables in your configured database (PostgreSQL via Supabase or SQLite).

#### 2. **Create a Superuser (Admin Account)**
```bash
python manage.py createsuperuser
```

Use this to access Django admin at: `http://127.0.0.1:8000/admin`

#### 3. **Add Initial Data** (Optional)
You can add facilities via Django admin or through API:

```bash
# Create a facility via shell
python manage.py shell
```

```python
from core.models import Facility, SportType

facility = Facility.objects.create(
    name="City Football Field",
    sport_type=SportType.FOOTBALL,
    is_indoor=False,
    description="Professional football pitch",
    location_name="Downtown Sports Complex",
    latitude=11.5564,
    longitude=104.9282,
    base_price_per_hour=50.00,
    is_active=True
)
print(f"Created: {facility}")
```

### Supabase Table Configuration

If using Supabase instead of SQLite, configure these as your `SUPABASE_BOOKING_TABLE` and `SUPABASE_TIMESLOT_TABLE`:

- `core_booking` - Maps to Booking model
- `core_timeslot` - Maps to TimeSlot model
- `core_facility` - Maps to Facility model

These are referenced in your `.env` file and used by the Django backend for API operations.

## �📁 File Locations Reference

| File | Location | Purpose |
|------|----------|---------|
| Backend `.env` | `backend/.env` | Django credentials, Supabase keys, Groq API key |
| Backend Example | `backend/.env.example` | Template for backend credentials |
| Frontend `.env` | `my_project/.env` | Flutter Supabase public keys |
| Frontend Example | `my_project/backend/.env.example` | Template for frontend (Flutter only) |

## 🔒 Security Guidelines

- ✅ **DO:** Add `.env` to `.gitignore` (already configured)
- ✅ **DO:** Keep API keys only on your local machine
- ✅ **DO:** Share `.env.example` with team members (no real keys)
- ❌ **DON'T:** Commit `.env` files to git
- ❌ **DON'T:** Share your actual API keys in messages or repositories

## 📚 Documentation

- [Flutter Documentation](https://docs.flutter.dev/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Supabase Documentation](https://supabase.com/docs)
- [Groq API Documentation](https://console.groq.com/docs)

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 👥 Contributing

1. Clone the repository
2. Create a feature branch (`git checkout -b feature/YourFeature`)
3. Commit your changes (`git commit -m 'Add YourFeature'`)
4. Push to the branch (`git push origin feature/YourFeature`)
5. Open a Pull Request
