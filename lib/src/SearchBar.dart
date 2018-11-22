import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loader_search_bar/src/StateHolder.dart';

import 'QuerySetLoader.dart';
import 'SearchBarAttrs.dart';
import 'SearchBarBuilder.dart';
import 'SearchItem.dart';

/// Search field widget being displayed within Scaffold element.
/// Depending on its state and passed attributes it can be rendered
/// as an appBar action, expanded to its full size when activated or merged
/// with appBar, making the search field visible although not activated.
///
/// SearchBar needs to be placed underneath Scaffold element in the
/// widget tree, in place of the original AppBar.
///
/// Specifying [onQueryChanged], [onQuerySubmitted] allows to receive callbacks
/// whenever user input occurs.
/// If [loader] argument is passed, data set will be automatically loaded when
/// query changes (or is submitted). When it happens, widget will change its
/// preferred size requested by Scaffold ancestor, making the ListView take
/// whole available space below app bar. Once user cancels search action
/// (navigates back) widget is rebuilt with default app bar size making
/// Scaffold body visible again.
class SearchBar extends StatefulWidget implements PreferredSizeWidget {
  SearchBar({
    @required this.defaultBar,
    this.onQueryChanged,
    this.onQuerySubmitted,
    this.loader,
    this.overlayStyle,
    this.searchHint = 'Tap to search...',
    this.initialQuery,
    this.controller,
    this.iconified = true,
    bool autofocus,
    SearchItem searchItem,
    SearchBarAttrs attrs,
  })  : this.autofocus = autofocus ?? iconified,
        this.searchItem = searchItem ?? SearchItem.action(),
        this.attrs = _initAttrs(iconified, attrs);

  static SearchBarAttrs _initAttrs(bool iconified, SearchBarAttrs attrs) {
    final defaultAttrs =
        iconified ? _defaultIconifiedAttrs : _defaultMergedAttrs;
    return attrs != null ? defaultAttrs.merge(attrs) : defaultAttrs;
  }

  static final _defaultIconifiedAttrs = SearchBarAttrs(
    textBoxBackgroundColor: Colors.transparent,
    textBoxOutlineColor: Colors.transparent,
  );

  static final _defaultMergedAttrs = SearchBarAttrs(
    textBoxBackgroundColor: Colors.black12,
    textBoxOutlineColor: Colors.black26,
  );

  /// Function being called whenever query changes with its current value
  /// as an argument.
  final ValueChanged<String> onQueryChanged;

  /// Function being called whenever query is submitted with its current value
  /// as an argument.
  final ValueChanged<String> onQuerySubmitted;

  /// Widget automatically loading data corresponding to current query
  /// and displaying it in ListView.
  final QuerySetLoader loader;

  /// SearchBarAttrs instance allowing to specify part of exact values used
  /// during widget building.
  final SearchBarAttrs attrs;

  /// AppBar widget that will be displayed whenever SearchBar is not in
  /// activated state.
  final AppBar defaultBar;

  /// Hint string being displayed until user inputs any text.
  final String searchHint;

  /// Query value displayed for the first time in search field.
  final String initialQuery;

  /// Controller object allowing to access some properties of current state.
  final SearchBarController controller;

  /// Indicating way of representing non-activated SearchBar:
  ///   true if widget should be showed as an action item in defaultAppBar,
  ///   false if widget should be merged with defaultAppBar.
  final bool iconified;

  /// Determining if search field should get focus once it becomes visible.
  final bool autofocus;

  /// Defining how to position and build search item widget in AppBar.
  final SearchItem searchItem;

  /// Status bar overlay brightness applied when widget is activated.
  final SystemUiOverlayStyle overlayStyle;

  @override
  Size get preferredSize => _shouldTakeWholeSpace
      ? _getAvailableSpace ?? attrs.searchBarSize
      : attrs.searchBarSize;

  bool get _shouldTakeWholeSpace =>
      loader != null && (_isThisOrLastActivated ?? false);

  bool get _isThisOrLastActivated =>
      SearchBarState._stateHolder[this]?.activated ??
      SearchBarState._stateHolder.lastOrNull?.activated;

  Size get _getAvailableSpace {
    final screenSize = MediaQueryData.fromWindow(window).size;
    return Size(screenSize.width, screenSize.height - attrs.loaderBottomMargin);
  }

  @override
  State createState() => SearchBarState();
}

class SearchBarState extends State<SearchBar> {
  static final _stateHolder = StateHolder<SearchBar, SearchBarState>();

  bool activated = false;

  bool focused = false;

  bool queryNotEmpty = false;

  bool isClearingQuery = false;

  bool expanded;

  FocusNode searchFocusNode = FocusNode();

  TextEditingController queryInputController;

  String loaderQuery;

  Orientation currentOrientation;

  QuerySetLoader get _safeLoader => widget.loader ?? QuerySetLoader.blank;

  EdgeInsets get screenPadding => MediaQuery.of(context).padding;

  VoidCallback get clearQueryCallback =>
      widget.controller?.onClearQuery ?? _onClearQuery;

  VoidCallback get cancelSearchCallback =>
      widget.controller?.onCancelSearch ?? _onCancelSearch;

  @override
  void initState() {
    super.initState();
    _stateHolder.add(this);
    queryInputController = TextEditingController(text: widget.initialQuery);
    expanded = !widget.iconified;
    queryInputController.addListener(_onQueryControllerChange);
    searchFocusNode.addListener(_onSearchFocusChange);
  }

  void _onQueryControllerChange() {
    queryNotEmpty = queryInputController.text.isNotEmpty;
    if (isClearingQuery) {
      isClearingQuery = false;
      onTextChange('');
    }
  }

  void onTextChange(String text) {
    setState(() {
      if (_safeLoader.loadOnEachChange) loaderQuery = text;
    });
    if (widget.onQueryChanged != null) widget.onQueryChanged(text);
  }

  void onTextSubmit(String text) {
    setState(() {
      if (!_safeLoader.loadOnEachChange) loaderQuery = text;
    });
    if (widget.onQuerySubmitted != null) widget.onQuerySubmitted(text);
  }

  void _onSearchFocusChange() {
    setState(() {
      focused = searchFocusNode.hasFocus;
      if (focused && !activated) {
        activated = true;
        widget.controller?.onActivatedChanged?.call(true);
      }
    });
  }

  void _onCancelSearch() {
    setState(() {
      if (activated) {
        activated = false;
        widget.controller?.onActivatedChanged?.call(false);
      }
      if (widget.iconified) expanded = false;
      loaderQuery = null;
    });
    searchFocusNode.unfocus();
    widget.loader?.clearData();
    _rebuildScaffold();
  }

  void _rebuildScaffold() {
    Future.delayed(
      Duration(milliseconds: 50),
      () => Scaffold.of(context).setState(() {}),
    );
  }

  void onPrefixSearchTap() {
    FocusScope.of(context).requestFocus(searchFocusNode);
    _highlightQueryText();
  }

  void _highlightQueryText() {
    queryInputController.selection = TextSelection(
      baseOffset: queryInputController.value.text.length,
      extentOffset: 0,
    );
  }

  void _onClearQuery() {
    if (queryNotEmpty) {
      _clearQueryField();
    } else {
      searchFocusNode.unfocus();
    }
  }

  void _clearQueryField() {
    isClearingQuery = true;
    queryInputController.clear();
    _focusSearchField();
  }

  void _focusSearchField() =>
      FocusScope.of(context).requestFocus(searchFocusNode);

  void onSearchAction() {
    setState(() {
      expanded = true;
      if (widget.iconified) {
        queryInputController.text = widget.initialQuery;
      }
    });
    _rebuildScaffold();
  }

  @override
  void dispose() {
    searchFocusNode.dispose();
    queryInputController.dispose();
    _stateHolder.remove(this);
    super.dispose();
  }

  Future<bool> onWillPop() {
    bool shouldPop;
    if (activated) {
      _onCancelSearch();
      shouldPop = false;
    } else {
      shouldPop = true;
    }
    return Future.value(shouldPop);
  }

  @override
  Widget build(BuildContext context) {
    widget.controller?._state = this;
    return SearchBarBuilder(this, context);
  }
}

class SearchBarController {
  SearchBarController({
    this.onCancelSearch,
    this.onClearQuery,
    this.onActivatedChanged,
  });

  final VoidCallback onCancelSearch;
  final VoidCallback onClearQuery;
  final ValueChanged<bool> onActivatedChanged;

  SearchBarState _state;

  void setQueryText(String text) => _state?.queryInputController?.text = text;
  void cancelSearch() => _state?._onCancelSearch();
  void clearQuery() => _state?._onClearQuery();
  bool get isEmpty => _state != null ? !_state.queryNotEmpty : null;
  bool get isActivated => _state.activated;
  bool get isFocused => _state.focused;
}
