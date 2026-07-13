import 'dart:convert';

class LoanAlertItem {
  const LoanAlertItem({
    required this.id,
    required this.title,
    required this.isbn,
    required this.libraryName,
    required this.libraryCode,
    this.homepage = '',
    this.coverUrl = '',
    this.lastStatus = '감시 중',
    required this.createdAt,
    this.lastCheckedAt,
    this.active = true,
    this.completed = false,
    this.failureCount = 0,
  });
  final String id;
  final String title;
  final String isbn;
  final String libraryName;
  final String libraryCode;
  final String homepage;
  final String coverUrl;
  final String lastStatus;
  final DateTime createdAt;
  final DateTime? lastCheckedAt;
  final bool active;
  final bool completed;
  final int failureCount;

  LoanAlertItem copyWith({
    String? lastStatus,
    DateTime? lastCheckedAt,
    bool? active,
    bool? completed,
    int? failureCount,
  }) => LoanAlertItem(
    id: id,
    title: title,
    isbn: isbn,
    libraryName: libraryName,
    libraryCode: libraryCode,
    homepage: homepage,
    coverUrl: coverUrl,
    lastStatus: lastStatus ?? this.lastStatus,
    createdAt: createdAt,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    active: active ?? this.active,
    completed: completed ?? this.completed,
    failureCount: failureCount ?? this.failureCount,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isbn': isbn,
    'libraryName': libraryName,
    'libraryCode': libraryCode,
    'homepage': homepage,
    'coverUrl': coverUrl,
    'lastStatus': lastStatus,
    'createdAt': createdAt.toIso8601String(),
    'lastCheckedAt': lastCheckedAt?.toIso8601String(),
    'active': active,
    'completed': completed,
    'failureCount': failureCount,
  };
  String encode() => jsonEncode(toJson());
  factory LoanAlertItem.fromJson(Map<String, dynamic> json) => LoanAlertItem(
    id: '${json['id']}',
    title: '${json['title']}',
    isbn: '${json['isbn']}',
    libraryName: '${json['libraryName']}',
    libraryCode: '${json['libraryCode']}',
    homepage: '${json['homepage'] ?? ''}',
    coverUrl: '${json['coverUrl'] ?? ''}',
    lastStatus: '${json['lastStatus'] ?? '감시 중'}',
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
    lastCheckedAt: DateTime.tryParse('${json['lastCheckedAt'] ?? ''}'),
    active: json['active'] != false,
    completed: json['completed'] == true,
    failureCount: json['failureCount'] is int
        ? json['failureCount'] as int
        : int.tryParse('${json['failureCount'] ?? 0}') ?? 0,
  );
}
