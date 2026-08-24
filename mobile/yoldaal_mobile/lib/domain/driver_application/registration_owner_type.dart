enum RegistrationOwnerType {
  applicant,
  otherIndividual,
  company;

  String get displayName => switch (this) {
    RegistrationOwnerType.applicant => 'Başvuru sahibinin kendisi',
    RegistrationOwnerType.otherIndividual => 'Başka gerçek kişi',
    RegistrationOwnerType.company => 'Şirket',
  };
}
