class GenreMapping {
  const GenreMapping({required this.label, this.apiCode});

  final String label;
  final String? apiCode;
}

class RegionMapping {
  const RegionMapping({required this.label, required this.apiCode});

  final String label;
  final String apiCode;
}

const genreMappings = <GenreMapping>[
  GenreMapping(label: '문학', apiCode: '8'),
  GenreMapping(label: '인문', apiCode: '1'),
  GenreMapping(label: '사회', apiCode: '3'),
  GenreMapping(label: '과학', apiCode: '4'),
  GenreMapping(label: '역사', apiCode: '9'),
  GenreMapping(label: '예술', apiCode: '6'),
  GenreMapping(label: '종교', apiCode: '2'),
  GenreMapping(label: '기술·공학', apiCode: '5'),
  GenreMapping(label: '건강', apiCode: '5'),
  GenreMapping(label: '경제·경영', apiCode: '3'),
  GenreMapping(label: '자기계발', apiCode: '1'),
  GenreMapping(label: '여행', apiCode: '9'),
  GenreMapping(label: '어린이·청소년'),
];

const ageGroups = <String>[
  '전체',
  '10대 이하',
  '10대',
  '20대',
  '30대',
  '40대',
  '50대',
  '60대 이상',
];
const genders = <String>['전체', '남성', '여성'];
const loanPeriods = <String>['최근 7일', '최근 30일', '최근 90일'];

const regionMappings = <RegionMapping>[
  RegionMapping(label: '서울특별시', apiCode: '11'),
  RegionMapping(label: '부산광역시', apiCode: '21'),
  RegionMapping(label: '대구광역시', apiCode: '22'),
  RegionMapping(label: '인천광역시', apiCode: '23'),
  RegionMapping(label: '광주광역시', apiCode: '24'),
  RegionMapping(label: '대전광역시', apiCode: '25'),
  RegionMapping(label: '울산광역시', apiCode: '26'),
  RegionMapping(label: '세종특별자치시', apiCode: '29'),
  RegionMapping(label: '경기도', apiCode: '31'),
  RegionMapping(label: '강원특별자치도', apiCode: '32'),
  RegionMapping(label: '충청북도', apiCode: '33'),
  RegionMapping(label: '충청남도', apiCode: '34'),
  RegionMapping(label: '전북특별자치도', apiCode: '35'),
  RegionMapping(label: '전라남도', apiCode: '36'),
  RegionMapping(label: '경상북도', apiCode: '37'),
  RegionMapping(label: '경상남도', apiCode: '38'),
  RegionMapping(label: '제주특별자치도', apiCode: '39'),
];

final regions = regionMappings
    .map((region) => region.label)
    .toList(growable: false);

String? genreCodeOf(String? label) {
  if (label == null || label == '전체') return null;
  for (final item in genreMappings) {
    if (item.label == label) return item.apiCode;
  }
  return null;
}

String? regionCodeOf(String? label) {
  if (label == null || label == '전체') return null;
  for (final item in regionMappings) {
    if (item.label == label) return item.apiCode;
  }
  return null;
}

String? ageCodeOf(String? label) => switch (label) {
  null || '전체' => null,
  '10대 이하' => '0',
  '10대' => '10',
  '20대' => '20',
  '30대' => '30',
  '40대' => '40',
  '50대' => '50',
  '60대 이상' => '60',
  _ => null,
};

String? genderCodeOf(String? label) => switch (label) {
  '남성' => '0',
  '여성' => '1',
  _ => null,
};
