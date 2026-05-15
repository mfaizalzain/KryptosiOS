# Kryptos — iOS Marketing Assets

```
marketing/
├── App-Store-Listing.md      ← all listing copy (name, subtitle, description, keywords, etc.)
├── icon-512.svg              ← brand mark source
├── icon-1024.png             ← App Store icon, 1024×1024 no-alpha (ready to upload)
└── screenshots/
    ├── screenshot-1..5.svg   ← source artboards (1080×2400)
    └── iphone-6.9/           ← 1320×2868 PNG, iPhone 16 Pro Max class (REQUIRED)
```

> The app target is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), so iPad screenshots are not required.

## Upload checklist

1. **Bump version & build** in Xcode → Kryptos target → General.
2. **Product → Archive**, then Distribute App → App Store Connect.
3. In App Store Connect:
   - Upload `icon-1024.png` as the App Store icon (App Information).
   - Upload all five `screenshots/iphone-6.9/screenshot-*.png` to the 6.9" slot.
   - Paste copy blocks from `App-Store-Listing.md` (Name, Subtitle, Promotional Text, Description, Keywords, What's New).
   - Fill App Privacy responses from the section in `App-Store-Listing.md`.
   - Confirm Export Compliance is exempt (already declared via `ITSAppUsesNonExemptEncryption=false` in `Kryptos-Info.plist`).
   - Create the `kryptos_pro_upgrade` Non-Consumable IAP ($1.99) and attach it to this version.
   - Paste the **Review Notes** block from `App-Store-Listing.md` into "Notes for Reviewer".
4. Submit for Review.

## Re-rendering screenshots

```bash
cd marketing/screenshots
for i in 1 2 3 4 5; do
  rsvg-convert -w 1320 "screenshot-$i.svg" -o /tmp/ks.png
  sips --cropToHeightWidth 2868 1320 /tmp/ks.png --out "iphone-6.9/screenshot-$i.png"
done
```

## Re-rendering icon (no-alpha required by App Store)

```bash
rsvg-convert -w 1024 -b "#0F1730" icon-512.svg -o icon-1024.png
```
