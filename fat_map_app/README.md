# FAT Map – تطبيق Flutter (نسخة تجريبية لأندرويد)

## الطريقة 1: البناء على GitHub (بدون تثبيت أي شيء)
1. ضع مجلد `fat_map_app` في جذر مستودعك (بجانب `index.html` و`data.csv`).
2. ضع ملف `.github/workflows/build-apk.yml` في جذر المستودع.
3. ارفع التغييرات (commit + push).
4. افتح تبويب **Actions** ‹ **Build APK**. إن لم يبدأ تلقائياً اضغط **Run workflow**.
5. بعد نجاح البناء (حوالي 10 دقائق في المرة الأولى) افتح الـ run ونزّل **fat-map-apk** من قسم Artifacts.
6. فك ضغط الملف، وانقل `app-release.apk` إلى الهاتف وثبّته.

## الطريقة 2: البناء على جهازك
يحتاج: Flutter SDK وAndroid Studio.
```bash
cd fat_map_app
mkdir -p assets && cp ../data.csv assets/data.csv
flutter create --org com.masiraq --project-name fat_map --platforms android .
python3 tool/patch_android.py
flutter pub get
flutter build apk --release
# الناتج: build/app/outputs/flutter-apk/app-release.apk
```
للتشغيل المباشر على هاتف موصول: `flutter run --release`

> ⚠️ اختبر السلاسة دائماً بنسخة **release**. نسخة debug أبطأ بكثير ولا تعبّر عن الأداء الحقيقي.

## ما الموجود في هذه النسخة
- خلفيات Google / Esri / OSM
- كل النقاط مع التجميع وألوان الشركاء والأسماء من زوم 17
- Usage وFilter 0 User
- البحث بالكود (مع اقتراحات) وبالإحداثيات العشرية
- الضغط على نقطة يعرض التفاصيل مع النسخ وفتح Google Maps، والضغط المطوّل يعرض الإحداثيات
- موقعي وزر تحديد الموقع
- رسالة عند الفتح بعدد النقاط والزمن الكلي للتحميل

## غير موجود بعد
أداة القياس، تدوير الخريطة بالبوصلة، التحويل التلقائي بين الخلفيات عند تعطّلها، تسجيل الزيارات، الإكمال التلقائي لصيغة الكود.

## الملفات
- `lib/main.dart`: الواجهة والخريطة
- `lib/data.dart`: قراءة data.csv في الخلفية وتحويلها إلى GeoJSON يقرؤه المحرك مباشرة
- `lib/style.dart`: الخلفيات
- `tool/patch_android.py`: صلاحيات أندرويد واسم التطبيق
