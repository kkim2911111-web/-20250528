import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PhotoUploadGrid extends StatefulWidget {
  static const maxPhotos = 10;

  static const photoGuides = [
    '차량 앞면',
    '차량 뒷면',
    '좌측면',
    '우측면',
    '실내',
    '계기판',
    '주차 위치',
    '기타 손상 부위',
  ];

  final List<Uint8List> photos;
  final ValueChanged<List<Uint8List>> onChanged;

  const PhotoUploadGrid({
    super.key,
    required this.photos,
    required this.onChanged,
  });

  @override
  State<PhotoUploadGrid> createState() => _PhotoUploadGridState();
}

class _PhotoUploadGridState extends State<PhotoUploadGrid> {
  static const _textPrimary = Color(0xFFEAF2FF);
  static const _textSecondary = Color(0xFF9AB3C9);

  final _picker = ImagePicker();

  Future<void> _addPhoto() async {
    if (widget.photos.length >= PhotoUploadGrid.maxPhotos) {
      _showSnack('사진은 최대 ${PhotoUploadGrid.maxPhotos}장까지 등록할 수 있습니다.');
      return;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final next = [...widget.photos, bytes];
    widget.onChanged(next);
  }

  Future<void> _takePhoto() async {
    if (widget.photos.length >= PhotoUploadGrid.maxPhotos) {
      _showSnack('사진은 최대 ${PhotoUploadGrid.maxPhotos}장까지 등록할 수 있습니다.');
      return;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    widget.onChanged([...widget.photos, bytes]);
  }

  void _removePhoto(int index) {
    final next = [...widget.photos]..removeAt(index);
    widget.onChanged(next);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '차량 사진',
              style: TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${widget.photos.length}/${PhotoUploadGrid.maxPhotos}',
              style: const TextStyle(color: _textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '앞·뒤·좌·우·실내·계기판 등 차량 상태를 확인할 수 있도록 촬영해주세요.',
          style: TextStyle(color: _textSecondary, height: 1.4, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: PhotoUploadGrid.photoGuides.map((guide) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF132A3D),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                guide,
                style: const TextStyle(color: _textSecondary, fontSize: 11),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < widget.photos.length; i++)
              _PhotoTile(
                bytes: widget.photos[i],
                onRemove: () => _removePhoto(i),
              ),
            if (widget.photos.length < PhotoUploadGrid.maxPhotos) ...[
              _AddPhotoButton(
                icon: Icons.photo_library_outlined,
                label: '앨범',
                onTap: _addPhoto,
              ),
              _AddPhotoButton(
                icon: Icons.photo_camera_outlined,
                label: '촬영',
                onTap: _takePhoto,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onRemove;

  const _PhotoTile({required this.bytes, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: Colors.black87,
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
            ),
            iconSize: 16,
            onPressed: onRemove,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AddPhotoButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: const Color(0xFF132A3D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF9AB3C9)),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9AB3C9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
