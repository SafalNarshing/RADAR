class Comment {
  final int id;
  final String content;
  final String? userId;
  final String? userName;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.content,
    this.userId,
    this.userName,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      content: json['content'],
      userId: json['user_id'],
      userName: json['profiles']?['full_name'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
