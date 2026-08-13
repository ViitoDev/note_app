/// Metadados de um item do Google Drive usados pelo app.
///
/// Mantemos o tipo gerado pela API fora do dominio para facilitar testes e
/// permitir trocar a implementacao HTTP sem contaminar a interface.
class DriveItem {
  const DriveItem({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.parentIds,
    this.modifiedTime,
    this.version,
    this.md5Checksum,
  });

  final String id;
  final String name;
  final String mimeType;
  final List<String> parentIds;
  final DateTime? modifiedTime;
  final String? version;
  final String? md5Checksum;

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';
}
