import '../models/srx_base_model.dart';
import '../viewmodels/srx_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controller/srx_session_controller.dart';

typedef Widget ListItem<T>(T item, BuildContext context);
typedef Widget BuildListViewFunction<T>(List<T> items, BuildContext context);

class SrxBaseListWidget<T extends SrxBaseModel, VM extends SrxListViewModel<T>> extends StatelessWidget {
  final ListItem<T>? listItem;
  final Widget loadingWidget;
  final Widget? noDataWidget;
  final SrxErrorWidget errorWidget;
  final bool refreshEnabled;
  final BuildListViewFunction? buildListView;

  SrxBaseListWidget({
    this.listItem,
    this.noDataWidget,
    required this.loadingWidget,
    required this.errorWidget,
    this.refreshEnabled = true,
    this.buildListView,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VM>(builder: (context, viewmodel, child) {
      return _buildWidget(viewmodel, context);
    });
  }

  Widget _buildWidget(viewmodel, BuildContext context) {
    if (viewmodel.isBusy) {
      return loadingWidget;
    } else {
      if (viewmodel.isError) {
        return errorWidget(viewmodel.errorMessage ?? '');
      } else if (viewmodel.items.isEmpty && noDataWidget != null) {
        return noDataWidget!;
      }
      return _buildList(viewmodel, context);
    }
  }

  Widget _buildList(VM vm, BuildContext context) {
    if (refreshEnabled) {
      return RefreshIndicator(
          onRefresh: () async {
            if (refreshEnabled) {
              context.read<VM>().loadData();
            }
          },
          child: _buildListView(vm.items, context));
    } else {
      return _buildListView(vm.items, context);
    }
  }

  Widget _buildListView(List<T> items, BuildContext context) {
    if (buildListView == null && listItem == null) {
      throw Exception('Either \'buildListView\' or \'listitem\' must be set!');
    }

    return buildListView != null
        ? buildListView!(items, context)
        : ListView.builder(itemCount: items.length, itemBuilder: (context, index) => listItem!(items.elementAt(index), context));
  }
}

typedef Widget SrxFormWidget<T extends SrxBaseModel, VM extends SrxBaseFormViewModel>(VM viewmodel);

class SrxBaseFormWidget<T extends SrxBaseModel, VM extends SrxBaseFormViewModel<T>> extends StatelessWidget {
  final Widget loadingView;
  final SrxErrorWidget errorView;
  final SrxFormWidget formWidget;

  SrxBaseFormWidget({
    required this.formWidget,
    required this.loadingView,
    required this.errorView,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VM>(builder: (context, viewmodel, child) {
      return viewmodel.isBusy
          ? loadingView
          : viewmodel.isError
              ? errorView(viewmodel.errorMessage ?? '')
              : _buildForm(viewmodel);
    });
  }

  Widget _buildForm(VM viewmodel) {
    return ReactiveForm(formGroup: viewmodel.form, child: formWidget(viewmodel));
  }
}

typedef Widget SrxErrorWidget<T>(String errorMessage);

class SrxBaseErrorWidget extends StatelessWidget {
  final String errorMessage;
  final void Function()? onRetry;

  SrxBaseErrorWidget({required this.errorMessage, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).errorColor,
              size: 60,
            ),
            SizedBox(height: 16),
            Text('srx.loadingerror.title'.tr(), style: Theme.of(context).textTheme.headline6),
            SizedBox(
              height: 6,
            ),
            Text('"$errorMessage"', style: Theme.of(context).textTheme.bodyText2, maxLines: 4, textAlign: TextAlign.center),
            SizedBox(height: 48),
            onRetry != null
                ? ElevatedButton(
                    onPressed: () {
                      if (onRetry != null) {
                        onRetry!();
                      }
                    },
                    child: Text('srx.common.refresh'.tr()))
                : Container(),
          ],
        ),
      ),
    );
  }
}

class SrxLoadingIndicatorWidget extends StatelessWidget {
  final Color? color;

  SrxLoadingIndicatorWidget({this.color});

  @override
  Widget build(BuildContext context) {
    return Center(child: CircularProgressIndicator(valueColor: color != null ? AlwaysStoppedAnimation<Color>(Colors.white) : null));
  }
}

class SrxNoDataWidget extends StatelessWidget {
  final String message = 'srx.common.no_records'.tr();
  final void Function()? onRetry;

  SrxNoDataWidget({String? message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${message.tr()}', style: Theme.of(context).textTheme.subtitle1, maxLines: 4),
          SizedBox(height: 16),
          onRetry != null
              ? ElevatedButton(
                  onPressed: () {
                    if (onRetry != null) {
                      onRetry!();
                    }
                  },
                  child: Text('srx.common.refresh'.tr()))
              : Container(),
        ],
      ),
    );
  }
}

typedef void SrxSideBarNavigationItemTap(int itemIndex);

class SrxSideBarNavigationWidget extends StatefulWidget {
  final List<SrxSideBarNavigationItem> sideBarItems;
  final Widget body;
  final int? _selectedIndex;
  final Function? onItemTap;

  const SrxSideBarNavigationWidget({required this.sideBarItems, required this.body, int? selectedIndex, this.onItemTap})
      : _selectedIndex = selectedIndex;

  @override
  _SrxSideBarNavigationWidgetState createState() => _SrxSideBarNavigationWidgetState(_selectedIndex);
}

class _SrxSideBarNavigationWidgetState extends State<SrxSideBarNavigationWidget> {
  int? _selectedIndex;

  _SrxSideBarNavigationWidgetState(int? selectedIndex) : _selectedIndex = selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Row(children: [
        SizedBox(
          width: 180,
          child: ListView(
            children: _buildItems(),
          ),
        ),
        VerticalDivider(
          width: 1,
        ),
        Expanded(child: widget.body),
      ]),
    );
  }

  List<ListTile> _buildItems() {
    return List.generate(
        widget.sideBarItems.length,
        (index) => ListTile(
              dense: true,
              minLeadingWidth: 24,
              contentPadding: EdgeInsets.fromLTRB(12, 6, 12, 6),
              leading: Icon(
                widget.sideBarItems[index].icon,
                size: 20,
                color: _selectedIndex == index ? Colors.white : Theme.of(context).textTheme.subtitle2!.color,
              ),
              title: Text(
                widget.sideBarItems[index].label,
                style: Theme.of(context)
                    .textTheme
                    .subtitle1!
                    .copyWith(color: _selectedIndex == index ? Colors.white : Theme.of(context).textTheme.subtitle2!.color),
              ),
              selected: _selectedIndex != null ? _selectedIndex == index : false,
              selectedTileColor: Theme.of(context).accentColor,
              hoverColor: Color.fromARGB(254, 220, 220, 220),
              onTap: () {
                setState(() {
                  _selectedIndex = index;
                  if (widget.onItemTap != null) {
                    widget.onItemTap!(_selectedIndex);
                  }
                });
              },
            ));
  }
}

class SrxSideBarNavigationItem {
  String label;
  IconData icon;

  SrxSideBarNavigationItem(this.label, this.icon);
}

class SrxLoginFormWidget extends StatelessWidget {
  final SrxSessionController sessionController;

  SrxLoginFormWidget(this.sessionController);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SrxLoginFormViewModel>(
        create: (context) => SrxLoginFormViewModel(sessionController),
        child: Consumer<SrxLoginFormViewModel>(builder: (context, viewmodel, child) {
          return viewmodel.isBusy
              ? SrxLoadingIndicatorWidget()
              : ReactiveForm(formGroup: viewmodel.form, child: _buildForm(viewmodel, context));
        }));
  }

  Widget _buildForm(SrxLoginFormViewModel viewmodel, BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _buildUsernameField(),
      SizedBox(
        height: 24,
      ),
      _buildPasswordField(viewmodel),
      SizedBox(
        height: 24,
      ),
      _buildError(viewmodel, context),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
            onPressed: () => _login(viewmodel),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('srx.loginform.loginbutton.label'.tr()),
            )),
      )
    ]);
  }

  Visibility _buildError(SrxLoginFormViewModel viewmodel, BuildContext context) {
    return Visibility(
        visible: viewmodel.isError,
        child: Container(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              viewmodel.errorMessage ?? '',
              style: Theme.of(context).textTheme.bodyText1?.copyWith(color: Theme.of(context).errorColor),
              textAlign: TextAlign.center,
              maxLines: 4,
            )));
  }

  ReactiveTextField<Object> _buildPasswordField(SrxLoginFormViewModel viewmodel) {
    return ReactiveTextField(
      textInputAction: TextInputAction.go,
      obscureText: viewmodel.isPasswordObscureText,
      decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'srx.loginform.password.label'.tr(),
          isDense: true,
          suffixIcon: IconButton(
              icon: Icon(Icons.visibility_rounded), onPressed: () => viewmodel.isPasswordObscureText = !viewmodel.isPasswordObscureText)),
      formControlName: SrxLoginFormViewModel.passwordField,
      validationMessages: (control) => {'required': 'srx.common.fieldrequired'.tr()},
    );
  }

  ReactiveTextField<Object> _buildUsernameField() {
    return ReactiveTextField(
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'srx.loginform.username.label'.tr(), isDense: true),
      formControlName: SrxLoginFormViewModel.usernameField,
      validationMessages: (control) => {'required': 'srx.common.fieldrequired'.tr()},
    );
  }

  void _login(SrxLoginFormViewModel viewmodel) async {
    viewmodel.form.markAllAsTouched();
    if (viewmodel.form.valid) {
      await viewmodel.login();
    }
  }
}

class SrxNavigationDrawerWidget extends StatelessWidget {
  final Widget? loginPage;
  final String? copyrightText;
  final Image? logo;
  final String? logoUrl;
  final bool showLogout;
  final SrxSessionController? sessionController;
  final String? developedByText;
  final String? developedByUrl;

  SrxNavigationDrawerWidget(
      {this.sessionController,
      this.loginPage,
      this.copyrightText,
      this.logo,
      this.logoUrl,
      this.showLogout = false,
      this.developedByText = 'developed by Sarix',
      this.developedByUrl = 'https://www.sarix.eu/'});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: PackageInfo.fromPlatform(),
        builder: (BuildContext context, AsyncSnapshot<PackageInfo> info) {
          return Drawer(
            child: buildDefaultItems(context, info),
          );
        });
  }

  Widget buildDefaultItems(BuildContext context, AsyncSnapshot<PackageInfo> info) {
    List<Widget> items = [];
    items.add(buildLogo());
    items.addAll(buildItems(context));
    items.add(Divider(thickness: 1));
    items.add(buildLogoutMenuItem(context));
    items.add(buildInfoTile(context, info));

    return Column(
      children: items,
    );
  }

  Expanded buildInfoTile(BuildContext context, AsyncSnapshot<PackageInfo> info) {
    return Expanded(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        buildInformationTile(context, info),
      ],
    ));
  }

  Visibility buildLogoutMenuItem(BuildContext context) {
    return Visibility(
      visible: showLogout,
      child: Column(
        children: [
          ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).primaryColor),
              title: Text('srx.common.logout'.tr()),
              dense: true,
              onTap: () => logout(context)),
          Divider(thickness: 1),
        ],
      ),
    );
  }

  Widget buildLogo() {
    return GestureDetector(
        onTap: () async => logoUrl != null ? await launch(logoUrl!) : null,
        child: SizedBox(
          height: 150,
          child: logo,
        ));
  }

  List<Widget> buildItems(BuildContext context) {
    return [];
  }

  void logout(BuildContext context) {
    if (sessionController == null) {
      throw Exception('Sessioncontroller is not set!');
    }
    sessionController!.logout();
    if (loginPage != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => loginPage!));
    }
  }

  Padding buildInformationTile(BuildContext context, AsyncSnapshot<PackageInfo> info) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Text(
            (info.data != null ? "v${info.data?.version} - " : "") + (copyrightText ?? ''),
            style: TextStyle(fontSize: 14, color: Theme.of(context).disabledColor),
            textAlign: TextAlign.center,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: () => launch(developedByUrl ?? ''),
                  child: Text(
                    developedByText ?? '',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
