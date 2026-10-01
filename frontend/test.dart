import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final url = 'http://13.234.30.131:5000/api/sessions?status=history';
  try {
    final res = await http.get(Uri.parse(url));
    final List sessions = jsonDecode(res.body);
    if (sessions.isNotEmpty) {
      final id = sessions.first['id'];
      print('First session ID: \$id');
      
      final pdfUrl = 'http://13.234.30.131:5000/api/reports/session/\$id/pdf';
      final pdfRes = await http.get(Uri.parse(pdfUrl));
      print('PDF Status Code: \${pdfRes.statusCode}');
      if (pdfRes.statusCode != 200) {
        print('PDF Error: \${pdfRes.body}');
      }
    }
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
