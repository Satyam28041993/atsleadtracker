/// Salutations offered on a contact-name field, in the order shown in any
/// dropdown built from this list.
const List<String> kNameSalutations = <String>[
  'Mr.',
  'Mrs.',
  'Ms.',
  'Dr.',
  'M/s.',
];

/// Recognises a salutation already typed at the start of a name, so a
/// dropdown selection replaces it instead of stacking a second one on top,
/// and callers like the quotation PDF's intro line can skip adding their own.
final RegExp _salutationPrefix = RegExp(
  r'^(mr|mrs|ms|miss|dr|shri|smt|m/s)\.?\s*',
  caseSensitive: false,
);

/// True when [name] already starts with a recognised salutation.
bool hasSalutation(String name) => _salutationPrefix.hasMatch(name.trim());

/// [name] with any leading salutation removed.
String stripSalutation(String name) =>
    name.trim().replaceFirst(_salutationPrefix, '').trimLeft();

/// Prepends [salutation] onto [name], replacing whatever salutation (if any)
/// was already there. A blank [salutation] just strips one off.
String applySalutation(String name, String? salutation) {
  final bare = stripSalutation(name);
  final chosen = salutation?.trim() ?? '';
  if (chosen.isEmpty) return bare;
  if (bare.isEmpty) return chosen;
  return '$chosen $bare';
}
