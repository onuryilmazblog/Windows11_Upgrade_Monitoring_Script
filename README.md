Version 1.0.6

# Windows11_Upgrade_Monitoring_Script


> SCCM Windows Servicing Update ile birlikte çalışmaktadır. Windows Servicing Update ile tamamen sessiz bir şekilde gönderim sağladığınız Windows 11 Update paketini EvaluationState değerlerini kontrol ederek izler ve tespit ettiği değerlere göre kullanıcıya özel hazırlanmış bildirimlerin gönderimini sağlar.

[Onur Yılmaz Blog Adresimden](https://onuryilmaz.blog/windows-11-upgrade-monitoring-script) detaylarını inceleyebilirsiniz.

["Config.xml"](Config.xml) dosyasından;

- scriptPath = Kurulum adresini,
- registeryPath = Kayıt defteri adresini,
- LogFolderPath = Log dosyasının adresini,
- UpgradeFileSize = Güncelleme dosya boyutunu,
- ForceUpdateDate = ForceRequired deadline tarihini,
- NeedDiskSize = Minumum gereken disk alanını,
- FileRevision = Güncelleme revize numarasını

belirleyebilirsiniz.

Bu script hiçbir garanti olmaksızın "OLDUĞU GİBİ" sağlanmaktadır. Kendi sorumluluğunuzda kullanınınız.
