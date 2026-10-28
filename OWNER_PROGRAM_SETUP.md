# Sports campus owner program

This feature adds an owner application, staff review, a monthly USD 20 subscription record, subscription-gated owner access, and booking analytics.

## Apply database changes

From the repository root:

```bash
cd backend
python manage.py migrate
python manage.py check
```

Migrations `0010_owner_application_subscription` and `0011_campus_profile_gallery` add the owner subscription workflow, campus profile, gallery photos, amenity and opening-hours metadata, and the optional campus relationship on facilities. No new app registration is required.

## Application and review flow

1. A signed-in user opens **Profile → Sports Campus Owner** and submits the venue details.
2. A Django staff/superuser reviews applications in Django admin or calls the review endpoint.
3. The owner sees the approved application and can create a pending $20 subscription checkout record.
4. Owner access is enabled only after a valid signed payment webhook activates the subscription.
5. A verified payment creates a `Campus` profile, its gallery photos, and an initial bookable `Facility` record using the application details.
6. The owner can edit the public campus page from **Profile → Sports Campus Owner** after the subscription is active.
7. Customers open the campus detail page from Explore to see photos, description, amenities, hours, contact, cancellation policy, and bookable facilities.

Review endpoint (staff/superuser only):

`POST /api/owner/applications/<application_id>/review/`

JSON body:

```json
{ "decision": "approve", "admin_note": "Verified campus details" }
```

Allowed decisions: `approve`, `reject`, `review`.

## Payment integration — required before launch

The checkout endpoint currently creates a **pending record only**; it does not collect money or redirect to a payment provider. The client confirmation endpoint is deliberately disabled so a user cannot grant themselves paid access.

Set a strong random `OWNER_PAYMENT_WEBHOOK_SECRET` in the backend environment. The generic webhook endpoint is:

`POST /api/owner/payment/webhook/`

It expects the provider adapter to send the raw JSON body signed as:

`X-Owner-Payment-Signature: sha256=<hex HMAC-SHA256 of raw request body>`

Expected success event shape:

```json
{
  "event": "payment.succeeded",
  "subscription_id": 123,
  "payment_reference": "provider-unique-payment-id",
  "amount": "20.00",
  "currency": "USD"
}
```

**Do not send this event from the Flutter client.** The signature must be produced server-to-server by a trusted payment-provider integration after independently verifying the transaction. Adapt the webhook payload and signature verification to the selected provider before production. The generic HMAC contract is not a ready-made ABA Pay, KHQR, Stripe, or other provider integration.

The current subscription period is 30 days. Confirm whether the commercial plan should be monthly recurring or a one-time 30-day pass before enabling real checkout.

## Endpoints

- `GET/POST /api/owner/applications/` — list the signed-in user's applications or submit one.
- `POST /api/owner/applications/<id>/review/` — staff review.
- `GET /api/owner/subscription/` — current/latest subscription state.
- `POST /api/owner/checkout/` — create a pending subscription record for an approved application.
- `POST /api/owner/payment/confirm/` — deliberately disabled; client-side confirmation is unsafe.
- `POST /api/owner/payment/webhook/` — signed server-to-server payment event.
- `GET /api/owner/analytics/` — subscription-gated facility and booking summary.
- `GET /api/campuses/` — public campus listing.
- `GET /api/campuses/<id>/` — public campus details, photos, amenities, policies, and facilities.
- `GET/PATCH /api/owner/campus/` — retrieve or update the subscribed owner's campus profile; gallery updates use `gallery_image_urls` (a list of image URLs).
- Existing `/api/facilities/owner/` endpoints remain the owner facility-management API and are now gated by staff status or active subscription.

## Analytics caveat

Booking revenue is currently calculated from the project's existing `mock_paid` booking payment status. It is useful for testing the dashboard, but it is not verified settlement accounting. Connect real booking-payment reconciliation before using it for financial reporting.
