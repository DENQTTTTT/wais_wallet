// Wais Wallet - built-in guesses for merchant -> category (Philippines)
// Category names must match the names in your categories table
// (Bills, Credit Card, Food, Health, Load / Data, Other, School, Shopping,
//  Subscriptions, Transport / Allowance, Other Income, Salary).
// Add your own keywords freely. The LONGEST matching keyword wins.

/// lowercase, letters/digits only, single spaces ("McDonald's!" -> "mcdonald s")
String normalizeMerchant(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// True when [keyword] appears in [text] as whole word(s). Both must already
/// be normalized.
bool merchantHasWord(String text, String keyword) {
  if (keyword.isEmpty) return false;
  return ' $text '.contains(' $keyword ');
}

class _Group {
  const _Group(this.type, this.category, this.keywords);
  final String type; // expense | income
  final String category;
  final List<String> keywords;
}

const _groups = <_Group>[
  _Group('expense', 'Food', [
    'jollibee', 'mcdo', 'mcdonald s', 'mcdonalds', 'mang inasal', 'chowking', 'greenwich',
    'starbucks', 'kfc', 'max s', 'maxs', 'yellow cab', 'shakey s', 'shakeys', 'pizza hut',
    'domino s', 'dominos', 'burger king', 'wendy s', 'tim hortons', 'dunkin', 'mister donut',
    'krispy kreme', 'army navy', 'kenny rogers', 'bonchon', 'mary grace', 'coffee bean',
    'cafe', 'coffee', 'milk tea', 'gong cha', 'coco', 'macao imperial', 'foodpanda',
    'grabfood', 'grab food', 'carinderia', 'turo turo', 'lugaw', 'samgyupsal', 'restaurant',
    'resto', 'bakery', 'pandesal', 'ulam', 'lunch', 'dinner', 'breakfast', 'merienda',
    'puregold', 'savemore', 'sm supermarket', 'sm hypermarket', 'robinsons supermarket',
    'landers', 's r', 'grocery', 'palengke', 'wet market', '7 eleven', '7eleven',
    'seven eleven', 'ministop', 'family mart', 'familymart', 'alfamart', 'treats',
  ]),
  _Group('expense', 'Transport', [
    'grab', 'grab car', 'angkas', 'joyride', 'move it', 'indrive', 'uber', 'taxi', 'mrt',
    'lrt', 'beep', 'easytrip', 'autosweep', 'toll', 'petron', 'shell', 'caltex', 'phoenix',
    'seaoil', 'unioil', 'gasoline', 'gas', 'fuel', 'diesel', 'jeep', 'jeepney', 'tricycle',
    'trike', 'bus', 'parking', 'cebu pacific', 'airasia', 'ferry', 'fare', 'pamasahe',
  ]),
  _Group('expense', 'Bills', [
    'meralco', 'maynilad', 'manila water', 'pldt', 'converge', 'sky cable', 'skycable',
    'cignal', 'water bill', 'electric bill', 'electric', 'kuryente', 'tubig', 'internet',
    'wifi', 'rent', 'upa', 'hoa', 'association dues', 'insurance', 'sss', 'philhealth',
    'pag ibig', 'pagibig', 'bir', 'tax', 'bayad center', 'bills',
  ]),
  _Group('expense', 'Load / Data', [
    'globe', 'smart', 'tnt', 'gomo', 'dito', 'sun cellular', 'load', 'data', 'prepaid',
    'promo', 'gigapoint', 'gigalife', 'gcash load',
  ]),
  _Group('expense', 'Shopping', [
    'shopee', 'lazada', 'zalora', 'shein', 'temu', 'tiktok shop', 'uniqlo', 'h m', 'zara',
    'nike', 'adidas', 'miniso', 'daiso', 'ikea', 'ace hardware', 'handyman', 'wilcon',
    'decathlon', 'mall', 'department store', 'sm store', 'clothes', 'shoes', 'damit', 'sapatos',
  ]),
  _Group('expense', 'Health', [
    'mercury drug', 'mercury', 'watsons', 'rose pharmacy', 'generika', 'southstar drug',
    'hospital', 'clinic', 'doctor', 'dental', 'dentist', 'pharmacy', 'botika', 'medicine',
    'gamot', 'laboratory', 'lab test', 'hmo', 'optical', 'vitamins', 'checkup',
  ]),
  _Group('expense', 'Subscriptions', [
    'netflix', 'spotify', 'youtube premium', 'disney', 'hbo', 'viu', 'prime video',
    'apple music', 'icloud', 'google one', 'chatgpt', 'openai', 'claude', 'canva', 'adobe',
    'microsoft 365', 'subscription', 'membership', 'gym',
  ]),
  _Group('expense', 'School', [
    'tuition', 'school', 'university', 'college', 'national bookstore', 'bookstore', 'books',
    'enrollment', 'miscellaneous fee', 'school supplies', 'project', 'thesis', 'printing',
  ]),
  _Group('expense', 'Credit Card', [
    'credit card', 'card payment', 'cc payment', 'cc',
  ]),
  _Group('income', 'Salary', [
    'salary', 'sweldo', 'payroll', '13th month', 'bonus', 'wage',
  ]),
  _Group('income', 'Allowance', [
    'allowance', 'baon', 'pocket money', 'padala',
  ]),
  _Group('income', 'Other Income', [
    'refund', 'interest', 'cashback', 'commission', 'sideline', 'benta', 'freelance',
  ]),
];

/// Category NAME guessed for [merchant] (null = unknown). The longest matching
/// keyword wins, so "grab food" -> Food but "grab" -> Transport.
String? builtInCategoryFor(String merchant, String type) {
  final text = normalizeMerchant(merchant);
  if (text.isEmpty) return null;
  String? best;
  var bestLen = 0;
  for (final g in _groups) {
    if (g.type != type) continue;
    for (final k in g.keywords) {
      if (k.length > bestLen && merchantHasWord(text, k)) {
        best = g.category;
        bestLen = k.length;
      }
    }
  }
  return best;
}
