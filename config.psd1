@{
    AvdName = 'Root_GMS_API_36'
    ApiLevel = 36
    Abi = 'x86_64'
    SourceTag = 'google_apis'
    CustomTag = 'google_apis_magisk'
    DeviceProfile = 'pixel_7'
    DataPartitionSize = '10G'
    RamSize = '2G'
    MinimumFreeSpaceGb = 12
    BuildToolsVersion = '36.0.0'

    MagiskVersion = '30.7'
    MagiskUrl = 'https://github.com/topjohnwu/Magisk/releases/download/v30.7/Magisk-v30.7.apk'
    MagiskSha256 = 'E0D32D2123532860F97123D927B1BB86C4E08E6FD8A48BFC6B5BEE0AFAE9EBD5'

    RootAvdCommit = '92df40eafa2f117053f56015e3c32ca706a55fa9'
    RootAvdArchiveUrl = 'https://github.com/galihlasahido/rootAVD/archive/92df40eafa2f117053f56015e3c32ca706a55fa9.zip'
    RootAvdUiTimeoutSeconds = 300

    MagiskModuleId = 'avd_magisk_su_bridge'
    RootProbePackage = 'com.example.rootprobe'
    GooglePlayServicesPackage = 'com.google.android.gms'
    GoogleServicesFrameworkPackage = 'com.google.android.gsf'
    BootTimeoutSeconds = 300
}
