import 'package:image_picker/image_picker.dart';
import '../main.dart';
import '../models/pothole.dart';
import '../models/comment.dart';

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
    const baseColumns =
        'id, latitude, longitude, severity, status, title, created_at';
    List<dynamic> data;
    try {
      // damage_type distinguishes pothole vs. crack markers on the map.
      // Falls back below if the column hasn't been added to the table yet.
      data = await supabase
          .from('potholes')
          .select('$baseColumns, damage_type')
          .order('created_at', ascending: false)
          .limit(500);
    } catch (_) {
      data = await supabase
          .from('potholes')
          .select(baseColumns)
          .order('created_at', ascending: false)
          .limit(500);
    }

    return data.map((e) => Pothole.fromJson(e)).toList();
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
      await supabase.from('profiles').insert({'id': userId, 'role': 'citizen'});
    }
  }

  static Future<void> submitReport({
    required double latitude,
    required double longitude,
    String? address,
    String? title,
    String? description,
    int severity = 3,
    DamageType? damageType,
    List<XFile> images = const [],
  }) async {
    await _ensureProfile();
    final userId = supabase.auth.currentUser!.id;

    final baseFields = {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'title': title,
      'description': description,
      'severity': severity,
      'reported_by': userId,
    };

    Map<String, dynamic> pothole;
    try {
      // damage_type may not exist on every environment's `potholes` table
      // yet — fall back to the base insert below if the column is missing.
      pothole = await supabase
          .from('potholes')
          .insert({
            ...baseFields,
            if (damageType != null)
              'damage_type': Pothole.damageTypeToDb(damageType),
          })
          .select()
          .single();
    } catch (_) {
      pothole = await supabase
          .from('potholes')
          .insert(baseFields)
          .select()
          .single();
    }

    for (int i = 0; i < images.length; i++) {
      final file = images[i];
      final ext = file.name.split('.').last.toLowerCase();
      final path =
          '${pothole['id']}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await file.readAsBytes();

      // uploadBinary (not upload, which needs dart:io File) works on both
      // mobile and web.
      await supabase.storage.from('pothole_media').uploadBinary(path, bytes);

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

  static Future<List<Comment>> getComments(int potholeId) async {
    final data = await supabase
        .from('comments')
        .select('id, content, created_at, user_id, profiles(full_name)')
        .eq('pothole_id', potholeId)
        .order('created_at', ascending: true);

    return (data as List).map((e) => Comment.fromJson(e)).toList();
  }

  static Future<void> addComment(int potholeId, String content) async {
    await _ensureProfile();
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('comments').insert({
      'pothole_id': potholeId,
      'content': content,
      'user_id': userId,
    });
  }
}
