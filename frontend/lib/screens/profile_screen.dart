import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/user_session.dart';
import '../widgets/app_drawer.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploading = false;

  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() { _isUploading = true; });

    try {
      final session = UserSession();
      final request = http.MultipartRequest('POST', Uri.parse('http://localhost:5000/api/auth/profile/picture'));
      request.headers['Authorization'] = 'Bearer ${session.token}';
      
      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('profile_pic', bytes, filename: image.name));
      
      final response = await request.send();
      if (response.statusCode == 200) {
        final resData = await response.stream.bytesToString();
        final json = jsonDecode(resData);
        setState(() {
          session.profilePicUrl = json['profile_pic_url'];
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to upload picture')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() { _isUploading = false; });
      }
    }
  }

  Future<void> _deleteProfilePicture() async {
    setState(() { _isUploading = true; });

    try {
      final session = UserSession();
      final response = await http.delete(
        Uri.parse('http://localhost:5000/api/auth/profile/picture'),
        headers: {
          'Authorization': 'Bearer ${session.token}',
        },
      );
      
      if (response.statusCode == 200) {
        setState(() {
          session.profilePicUrl = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture removed')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove picture')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() { _isUploading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = UserSession();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A2A42), Color(0xFF0F172A)],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5), width: 4),
                      boxShadow: [
                        const BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5)),
                      ],
                      image: session.profilePicUrl != null
                          ? DecorationImage(
                              image: NetworkImage('http://localhost:5000${session.profilePicUrl}'),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: session.profilePicUrl == null
                        ? Center(
                            child: Text(
                              (session.fullName ?? 'U').isNotEmpty ? (session.fullName ?? 'U')[0].toUpperCase() : 'U',
                              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          )
                        : null,
                  ),
                  GestureDetector(
                    onTap: _isUploading ? null : _pickAndUploadImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                        ]
                      ),
                      child: _isUploading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.camera_alt, color: AppTheme.primaryColor, size: 20),
                    ),
                  ),
                  if (session.profilePicUrl != null)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _isUploading ? null : _deleteProfilePicture,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                            ]
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              session.fullName ?? 'User Name',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 4),
            Text(
              session.employeeId ?? 'EMP-ID',
              style: const TextStyle(fontSize: 16, color: AppTheme.subtitleColor),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
              ),
              child: Text(
                session.displayRole,
                style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 32),
            _buildInfoCard(
              title: 'Account Details',
              children: [
                _buildInfoRow(Icons.email_outlined, 'Email', session.email ?? 'Not provided'),
                const Divider(),
                _buildInfoRow(Icons.work_outline, 'Designation', session.designation ?? 'Not specified'),
              ],
            ),
            const SizedBox(height: 16),
            if (session.isYardAdmin)
              _buildInfoCard(
                title: 'Assigned Yards',
                children: [
                  if (session.assignedYards.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('No yards currently assigned.', style: TextStyle(color: AppTheme.subtitleColor)),
                    )
                  else
                    ...session.assignedYardNames.map((yardName) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              const Icon(Icons.account_tree, size: 16, color: AppTheme.primaryColor),
                              const SizedBox(width: 8),
                              Text(yardName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                ],
              ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  session.clear();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text('LOGOUT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.subtitleColor, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
            ],
          ),
        ],
      ),
    );
  }
}
