import 'dart:math';
import 'dart:ui';

import 'package:essentiel/about.dart';
import 'package:essentiel/game/cards.dart';
import 'package:essentiel/game/category_selector_dialog.dart';
import 'package:essentiel/resources/category.dart';
import 'package:essentiel/utils.dart';
import 'package:essentiel/widgets/animated_background.dart';
import 'package:essentiel/widgets/animated_wave.dart';
import 'package:essentiel/widgets/particles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gsheets/gsheets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shake/shake.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcase.dart';
import 'package:showcaseview/showcase_widget.dart';

const _credentials = r'''
{
  "type": "service_account",
  "project_id": "essentiel-app",
  "private_key_id": "xxx",
  "private_key": "xxx",
  "client_email": "xxx",
  "client_id": "xxx",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "xxx"
}
''';

const _spreadsheetId = '1cR8lE6eCvDrgUXAVD1bmm36j6v5MtOEurSOAEfrTcCI';

const title = 'Jeu Essentiel';

//Inpiration from https://dribbble.com/shots/7696045-Tarot-App-Design
class Game extends StatefulWidget {
  @override
  _GameState createState() => _GameState();
}

class _GameState extends State<Game> {
  List<EssentielCardData> _rawCardsData;
  List<EssentielCardData> _allCardsData;
  Object _errorWhileLoadingData;
  int _currentIndex;
  bool _doShuffleCards;
  bool _applyFilter;
  List<String> _categoryListFilter;

  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  GlobalKey _cardListShowcaseKey = GlobalKey();
  BuildContext myContext;

  @override
  void initState() {
    super.initState();
    _doShuffleCards = false;
    _applyFilter = false;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final categoryListFilter = prefs.getStringList(CATEGORY_FILTER_PREF_KEY);
      debugPrint("Initial state for categoryListFilter: $categoryListFilter");
      final gsheets = GSheets(_credentials);
      gsheets
          .spreadsheet(_spreadsheetId)
          .then((spreadsheet) =>
              spreadsheet.worksheetByTitle('Questions').values.map.allRows())
          .then((questionsListJson) => Future.value((questionsListJson == null)
              ? <EssentielCardData>[]
              : questionsListJson
                  .map((questionJson) =>
                      EssentielCardData.fromGSheet(questionJson))
                  .where((element) =>
                      element.category != null &&
                      element.question != null &&
                      element.question.trim().isNotEmpty)
                  .toList()))
          .then((cardData) async {
        setState(() {
          _errorWhileLoadingData = null;
          _doShuffleCards = false;
          _applyFilter = false;
          _categoryListFilter = categoryListFilter;
          _rawCardsData = cardData.toList(growable: false);
          _allCardsData = _filter(_categoryListFilter);
        });
        await AppUtils.isFirstLaunch().then((result) {
          if (result) {
            if (myContext != null) {
              ShowCaseWidget.of(myContext)
                  .startShowCase([_cardListShowcaseKey]);
            }
          }
        });
      }).catchError((e) {
        setState(() {
          _errorWhileLoadingData = e;
          _rawCardsData = null;
          _allCardsData = null;
          _doShuffleCards = false;
          _applyFilter = false;
          _categoryListFilter = categoryListFilter;
        });
      });
    });

    ShakeDetector.autoStart(onPhoneShake: () {
      _randomDraw();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final categoryValues = Category.values;

    Widget body;
    if (_errorWhileLoadingData != null) {
      //Oh no!
      body = Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          Icons.error,
          color: Colors.redAccent,
          size: 50,
        ),
        SizedBox(
          height: 20.0,
        ),
        Flexible(
            child: Text(
                "Une erreur s'est produite. Merci de réessayer dans quelques instants.\n\n$_errorWhileLoadingData",
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 24, height: 1.7, color: Colors.white))),
      ]));
    } else if (_doShuffleCards || _applyFilter || _allCardsData == null) {
      //Not initialized yet
      body = Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SpinKitCubeGrid(
          size: 100.0,
          itemBuilder: (BuildContext context, int idx) => DecoratedBox(
              decoration: BoxDecoration(
                  color: categoryValues[idx < categoryValues.length
                          ? idx
                          : (idx % categoryValues.length)]
                      .color())),
        ),
        SizedBox(
          height: 20.0,
        ),
        Flexible(
            child: Text(
                (_doShuffleCards
                        ? "Mélange de cartes"
                        : _applyFilter
                            ? "Filtrage des catégories de cartes"
                            : "Initialisation") +
                    " en cours. Merci de patienter quelques instants...",
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 24, height: 1.7, color: Colors.white))),
      ]));
    } else if (_allCardsData.isEmpty) {
      //No data
      body = Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          Icons.error,
          color: Colors.orangeAccent,
          size: 50,
        ),
        SizedBox(
          height: 20.0,
        ),
        Flexible(
            child: Text(
                "Aucune donnée trouvée pour initialiser le jeu. Merci de réessayer dans quelques instants.",
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 24, height: 1.7, color: Colors.white))),
      ]));
    } else {
      //Yeah - we have some data !
      Widget widgetToDisplay;
      if (_currentIndex == null) {
        widgetToDisplay = Container(
            // height: screenHeight * 0.4,
            padding: const EdgeInsets.all(10.0),
            child: Center(
                child: Text(
                    "Cliquez sur une carte ou choisissez-en une au hasard à l'aide du menu tout en bas.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 24, height: 1.7, color: Colors.white))));
      } else {
        final cardData = _allCardsData.elementAt(_currentIndex);
        widgetToDisplay = Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.black, width: 2.0),
                color: Colors.white),
            // height: screenHeight * 0.1,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Stack(
                children: [
                  if (cardData.isForFamilies)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Image.asset(
                          'assets/images/family.png',
                          fit: BoxFit.scaleDown,
                          height: 60.0,
                          width: 60.0,
                          // colorBlendMode: ,
                        ),
                      ),
                    ),
                  if (cardData.isForCouples)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Image.asset(
                          'assets/images/couple.png',
                          fit: BoxFit.scaleDown,
                          height: 60.0,
                          width: 60.0,
                          // colorBlendMode: ,
                        ),
                      ),
                    ),
                  if (cardData.isForInternalMood)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.wb_sunny,
                              color: const Color(0xFFF7B900),
                              size: 40.0,
                            ),
                            FaIcon(
                              FontAwesomeIcons.cloudSun,
                              color: const Color(0xFFb5a347),
                              size: 35.0,
                            ),
                            FaIcon(
                              FontAwesomeIcons.cloudSunRain,
                              color: Colors.blueGrey,
                              size: 35.0,
                            ),
                            FaIcon(
                              FontAwesomeIcons.cloudRain,
                              color: Colors.blue,
                              size: 35.0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  Center(
                    child: SingleChildScrollView(
                      child: Text(
                        cardData.question,
                        style: TextStyle(
                            fontSize: 30.0,
                            color: cardData.category.color(),
                            wordSpacing: 2.0,
                            height: 1.75,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Positioned.fill(
                      child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: cardData.category.color(),
                      ),
                      child: Text(
                        cardData.category.title(),
                        style: TextStyle(
                          fontSize: 22.0,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )),
                ],
              ),
            ));
      }
      body = Column(
        children: [
          Expanded(
            flex: 4,
            child: widgetToDisplay,
          ),
          SizedBox(
            height: screenHeight * 0.05,
          ),
          Expanded(
              flex: 1,
              child: Showcase(
                key: _cardListShowcaseKey,
                descTextStyle: TextStyle(
                  fontSize: 20.0,
                ),
                overlayOpacity: 0.6,
                contentPadding:
                    const EdgeInsets.only(left: 25.0, top: 5.0, bottom: 5.0),
                description:
                    'Faites défiler de gauche à droite pour découvrir plus de cartes',
                child: AnimationLimiter(
                  child: ScrollablePositionedList.builder(
                    physics: BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    // clipBehavior: Clip.none,
                    scrollDirection: Axis.horizontal,
                    itemScrollController: itemScrollController,
                    itemPositionsListener: itemPositionsListener,
                    // shrinkWrap: true,
                    itemCount: _allCardsData.length,
                    itemBuilder: (BuildContext context, int index) =>
                        AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 175),
                      child: Align(
                        // widthFactor: (_currentIndex == index) ? 1.25 : 0.4,
                        alignment: Alignment.topCenter,
                        child: SlideAnimation(
                          horizontalOffset: 50.0,
                          child: FadeInAnimation(
                            child: GestureDetector(
                                child: Container(
                                  margin: const EdgeInsets.only(left: 5.0),
                                  child: EssentielCardWidget(
                                      index: index,
                                      selected: _currentIndex == index,
                                      noCardSelected: _currentIndex == null,
                                      cardData: _allCardsData.elementAt(index)),
                                ),
                                onTap: () {
                                  //TODO Animate card selection
                                  if (_currentIndex == index) {
                                    setState(() {
                                      _currentIndex = null;
                                      _doShuffleCards = false;
                                      _applyFilter = false;
                                    });
                                  } else {
                                    _jumpTo(index);
                                  }
                                }),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ))
        ],
      );
    }

    final toDisplay = Stack(
      children: [
        Positioned.fill(child: AnimatedBackground()),
        (_allCardsData != null)
            ? Positioned.fill(child: Particles(10))
            : Container(),
        _onBottom(AnimatedWave(
          height: 180,
          speed: 1.0,
        )),
        _onBottom(AnimatedWave(
          height: 120,
          speed: 0.9,
          offset: pi,
        )),
        _onBottom(AnimatedWave(
          height: 220,
          speed: 1.2,
          offset: pi / 2,
        )),
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(
                top: screenHeight * 0.085, left: 10.0, right: 10.0),
            child: Text(
              title,
              style: TextStyle(fontSize: 28.0, color: Colors.white),
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
              alignment: Alignment.center,
              child: Container(
                padding: EdgeInsets.only(
                    top: screenHeight * 0.2,
                    bottom: screenHeight * 0.13,
                    left: 10.0,
                    right: 10.0),
                // height: screenHeight * 0.5,
                child: body,
              )),
        ),
      ],
    );

    if (_doShuffleCards) {
      Future.delayed(Duration(milliseconds: 500), () {
        setState(() {
          _currentIndex = null;
          _allCardsData.shuffle();
          _doShuffleCards = false;
          _applyFilter = false;
        });
      });
    } else if (_applyFilter) {
      Future.delayed(Duration(milliseconds: 500), () {
        setState(() {
          _currentIndex = null;
          _allCardsData = _filter(_categoryListFilter);
          _doShuffleCards = false;
          _applyFilter = false;
        });
      });
    }

    final Map<String, Category> allCategoryTitlesMap = {
      for (var cat in categoryValues) cat.title(): cat
    };

    final allCategoryFilters = allCategoryTitlesMap.keys.toList()
      ..addAll(["Familles", "Couples"]);

    final chipColorFn = (String category) {
      final categoryForText = allCategoryTitlesMap[category];
      if (categoryForText != null) {
        return categoryForText.color();
      }
      if (category == "Couples") {
        return Colors.pink;
      }
      if (category == "Familles") {
        return Colors.brown;
      }
      return null;
    };

    return ShowCaseWidget(
      onStart: (index, key) {
        debugPrint('onStart: $index, $key');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          itemScrollController
              .scrollTo(
                  index: min(5, _allCardsData.length - 1),
                  duration: Duration(seconds: 1),
                  curve: Curves.easeInOutCubic)
              .whenComplete(() async {
            Future.delayed(
                Duration(seconds: 1),
                () => itemScrollController.scrollTo(
                    index: 0,
                    duration: Duration(seconds: 1),
                    curve: Curves.easeInOutCubic));
          });
        });
      },
      builder: Builder(
        builder: (ctx) {
          myContext = ctx;
          return Scaffold(
            body: toDisplay,
            floatingActionButton: (_rawCardsData != null &&
                    _rawCardsData.isNotEmpty)
                ? SpeedDial(
                    animatedIcon: AnimatedIcons.menu_close,
                    animatedIconTheme: IconThemeData(size: 22.0),
                    overlayColor: Colors.black,
                    overlayOpacity: 0.5,
                    tooltip: 'Menu',
                    heroTag: 'essentiel-speed-dial-hero-tag',
                    elevation: 8.0,
                    shape: CircleBorder(),
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.lightGreen,
                    curve: Curves.bounceIn,
                    children: [
                      SpeedDialChild(
                        child: Icon(Icons.info_outline),
                        backgroundColor: Category.SERVICE.color(),
                        label: 'À propos',
                        labelBackgroundColor: Category.SERVICE.color(),
                        labelStyle:
                            TextStyle(fontSize: 18.0, color: Colors.white),
                        onTap: () => showAppAboutDialog(context),
                      ),
                      SpeedDialChild(
                          child: Icon(Icons.filter_alt_sharp),
                          backgroundColor: Category.FORMATION.color(),
                          label: 'Filter les catégories de carte',
                          labelBackgroundColor: Category.FORMATION.color(),
                          labelStyle:
                              TextStyle(fontSize: 18.0, color: Colors.white),
                          onTap: () async => showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (BuildContext ctx) =>
                                  CategorySelectorDialog(
                                    title: Text(
                                      'Catégories à afficher',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20.0),
                                    ),
                                    all: allCategoryFilters,
                                    selected: _categoryListFilter,
                                    textBackgroundColorProvider:
                                        (String category, bool isSelected) {
                                      return isSelected
                                          ? chipColorFn(category)
                                          : Colors.grey[200];
                                    },
                                    textColorProvider:
                                        (String category, bool isSelected) {
                                      return isSelected
                                          ? Colors.white
                                          : chipColorFn(category);
                                    },
                                    callback: (List<String>
                                        selectedCategories) async {
                                      debugPrint(
                                          "selectedCategories: $selectedCategories");
                                      if (selectedCategories != null &&
                                          selectedCategories.isNotEmpty) {
                                        final prefs = await SharedPreferences
                                            .getInstance();
                                        prefs.setStringList(
                                            CATEGORY_FILTER_PREF_KEY,
                                            selectedCategories);
                                        setState(() {
                                          _categoryListFilter =
                                              selectedCategories;
                                          _applyFilter = true;
                                          _doShuffleCards = false;
                                        });
                                      }
                                    },
                                  ))
                          // onTap: () async {
                          //   await FilterListDialog.display(context,
                          //       allTextList: allCategoryFilters,
                          //       height: 480,
                          //       borderRadius: 20,
                          //       headlineText: "Catégories de carte à afficher",
                          //       hideSearchField: true,
                          //       selectedTextList: _categoryListFilter,
                          //       onApplyButtonClick: (list) async {
                          //     if (list != null) {
                          //       final selectedCategories =
                          //           list.map((e) => e.toString()).toList();
                          //       final prefs = await SharedPreferences.getInstance();
                          //       prefs.setStringList(
                          //           CATEGORY_FILTER_PREF_KEY, selectedCategories);
                          //       setState(() {
                          //         _categoryListFilter = selectedCategories;
                          //         _applyFilter = true;
                          //         _doShuffleCards = false;
                          //       });
                          //     }
                          //     Navigator.pop(context);
                          //   });
                          // },
                          ),
                      SpeedDialChild(
                        child: Icon(Icons.shuffle_outlined),
                        backgroundColor: Category.PRIERE.color(),
                        label: 'Mélanger les cartes',
                        labelBackgroundColor: Category.PRIERE.color(),
                        labelStyle:
                            TextStyle(fontSize: 18.0, color: Colors.white),
                        onTap: _shuffleCards,
                      ),
                      SpeedDialChild(
                          child: Icon(Icons.find_replace_outlined),
                          backgroundColor: Category.EVANGELISATION.color(),
                          label: 'Choisir une carte au hasard',
                          labelBackgroundColor: Category.EVANGELISATION.color(),
                          labelStyle:
                              TextStyle(fontSize: 18.0, color: Colors.white),
                          onTap: _randomDraw),
                    ],
                  )
                : null,
          );
        },
      ),
    );
  }

  List<EssentielCardData> _filter(List<String> filter) {
    if (filter == null) {
      return _rawCardsData;
    }
    if (filter.isEmpty) {
      return List.empty(growable: true);
    }
    return _rawCardsData.where((cardData) {
      if (_categoryListFilter.contains(cardData.category.title())) {
        return true;
      }
      if (_categoryListFilter.contains("Familles") && cardData.isForFamilies) {
        return true;
      }
      if (_categoryListFilter.contains("Couples") && cardData.isForCouples) {
        return true;
      }
      return false;
    }).toList();
  }

  void _shuffleCards() {
    setState(() {
      _doShuffleCards = true;
      _applyFilter = false;
    });
  }

  void _randomDraw() {
    if (_allCardsData == null || _allCardsData.isEmpty) {
      return;
    }
    final _numberOfCards = _allCardsData.length;
    final randomPick = RandomUtils.getRandomValueInRangeButExcludingValue(
        0, _numberOfCards, _currentIndex);
    debugPrint(
        "_numberOfCards=$_numberOfCards / _currentPageIndex=$_currentIndex / randomPick=$randomPick");
    _jumpTo(randomPick);
  }

  _onBottom(Widget child) => Positioned.fill(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      );

  _jumpTo(int index) => itemScrollController
          .scrollTo(
              index: max(0, index - 1),
              duration: Duration(milliseconds: 200),
              curve: Curves.easeInOutCubic)
          .whenComplete(() {
        setState(() {
          _currentIndex = index;
          _doShuffleCards = false;
          _applyFilter = false;
        });
      });
}

class EssentielCardWidget extends StatelessWidget {
  final EssentielCardData cardData;
  final bool selected;
  final bool noCardSelected;
  final int index;

  const EssentielCardWidget(
      {Key key,
      @required this.index,
      @required this.cardData,
      this.selected = false,
      this.noCardSelected = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return
        // Transform.scale(
        //   scale: selected ? 1.0 : 0.9,
        //   child:
        ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                    Colors.grey,
                    (noCardSelected || selected)
                        ? BlendMode.dstOver
                        : BlendMode.darken),
                child: Container(
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.black, width: 2.0),
                      color: Colors.white),
                  padding: EdgeInsets.all(15),
                  height: screenHeight * 0.3,
                  width: screenWidth * 0.25,
                  child: Image.asset("assets/images/essentiel_logo.svg.png",
                      fit: BoxFit.fill),
                ))
            // )
            );
  }
}
