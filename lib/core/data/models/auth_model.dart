class Auth {
  final String licence;
  final String id;
  final String password;

  Auth({required this.licence, required this.id, required this.password});

  // Permet de dupliquer l'objet avec un champ modifié
  Auth copyWith({String? licence, String? id, String? password}) {
    return Auth(
      licence: licence ?? this.licence,
      id: id ?? this.id,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() => {
    'licence': licence,
    'id': id,
    'password': password,
  };

  factory Auth.fromJson(Map<String, dynamic> json) => Auth(
    licence: json['licence'],
    id: json['id'],
    password: json['password'],
  );
}
