import 'dart:io';
import '../main.dart';
import '../models/pothole.dart';

class SupabaseService {
  static Future<List<Pothole>> getFeed({int page = 1}) async {
    final from = (page - 1) * 20;
    final to = from + 19;

    final data = await supabase
        .from('potholes')
        .select('''
          *,
          reported_by_profile:profiles!reported_by(full_name, avatar_url),
          pothole_media(file_path, is_primary, media_type)
        ''')
        .order('created_at', ascending: false)
        .range(from, to);

    return (data as List).map((e) => Pothole.fromJson(e)).toList();
  }

  static Future<List<Pothole>> getMyReports() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final data = await supabase
        .from('potholes')
        .select('''
          *,
          reported_by_profile:profiles!reported_by(full_name, avatar_url),
          pothole_media(file_path, is_primary, media_type)
        ''')
        .eq('reported_by', userId)
        .order('created_at', ascending: false);

    return (data as List).map((e) => Pothole.fromJson(e)).toList();
  }

  // Lightweight query for map markers — skips the profile/media joins
  // getFeed needs since the map only renders position + status/severity.
  static Future<List<Pothole>> getMapMarkers() async {
    final data = await supabase
        .from('potholes')
        .select('id, latitude, longitude, severity, status, title, created_at')
        .order('created_at', ascending: false)
        .limit(500);

    return (data as List).map((e) => Pothole.fromJson(e)).toList();
  }

  // Guards against reports/upvotes failing a FK constraint on `profiles`
  // when the current session's profile row wasn't created at sign-in
  // (e.g. a stale cached session from before the profiles upsert existed).
  static Future<void> _ensureProfile() async {
    final userId = supabase.auth.currentUser!.id;
    final existing = await supabase
        .from('profiles')
        .select('id')
        .eq('id', userId)
        .maybeSingle();
    if (existing == null) {
      await supabase.from('profiles').insert({
        'id': userId,
        'role': 'citizen',
      });
    }
  }

  static Future<void> submitReport({
    required double latitude,
    required double longitude,
    String? address,
    String? title,
    String? description,
    int severity = 3,
    List<File> images = const [],
  }) async {
    await _ensureProfile();
    final userId = supabase.auth.currentUser!.id;

    final pothole = await supabase
        .from('potholes')
        .insert({
          'latitude': latitude,
          'longitude': longitude,
          'address': address,
          'title': title,
          'description': description,
          'severity': severity,
          'reported_by': userId,
        })
        .select()
        .single();

    for (int i = 0; i < images.length; i++) {
      final file = images[i];
      final ext = file.path.split('.').last.toLowerCase();
      final path = '${pothole['id']}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage.from('pothole_media').upload(path, file);

      await supabase.from('pothole_media').insert({
        'pothole_id': pothole['id'],
        'file_path': path,
        'media_type': 'image',
        'is_primary': i == 0,
        'uploaded_by': userId,
      });
    }
  }

  // Returns true if now upvoted, false if removed
  static Future<bool> toggleUpvote(int potholeId) async {
    await _ensureProfile();
    final userId = supabase.auth.currentUser!.id;

    final existing = await supabase
        .from('upvotes')
        .select()
        .eq('pothole_id', potholeId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      await supabase
          .from('upvotes')
          .delete()
          .eq('pothole_id', potholeId)
          .eq('user_id', userId);
      return false;
    } else {
      await supabase.from('upvotes').insert({
        'pothole_id': potholeId,
        'user_id': userId,
      });
      return true;
    }
  }

  static Future<Set<int>> getUserUpvotes(List<int> potholeIds) async {
    if (potholeIds.isEmpty) return {};
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return {};

    final data = await supabase
        .from('upvotes')
        .select('pothole_id')
        .eq('user_id', userId)
        .inFilter('pothole_id', potholeIds);

    return (data as List).map<int>((e) => e['pothole_id'] as int).toSet();
  }

  static String getImageUrl(String path) {
    return supabase.storage.from('pothole_media').getPublicUrl(path);
  }

  static Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  static Future<Map<String, dynamic>?> getCurrentProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    return await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
  }
}
