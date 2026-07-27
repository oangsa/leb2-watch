# Room loads generated database implementations with a zero-argument
# constructor via reflection. Preserve that constructor after shrinking.
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>();
}
