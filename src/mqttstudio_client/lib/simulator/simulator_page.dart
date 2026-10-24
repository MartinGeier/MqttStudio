import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mqttstudio/common/widgets/error_snackbar.dart';
import 'package:mqttstudio/simulator/simulator_viewmodel.dart';
import 'package:mqttstudio/simulator/widgets/simulation_list.dart';
import 'package:mqttstudio/simulator/widgets/simulator_command_bar.dart';
import 'package:provider/provider.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:mqttstudio/custom_theme.dart';

// The SIMULATOR tab: publishes generated messages of simulated devices
class SimulatorPage extends StatefulWidget {
  const SimulatorPage({Key? key}) : super(key: key);

  @override
  State<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends State<SimulatorPage> {
  late final SimulatorViewmodel _viewmodel;

  @override
  void initState() {
    super.initState();
    _viewmodel = SimulatorViewmodel()
      ..onError = _showError
      ..onStoppedByDisconnect = _showStoppedByDisconnect;
  }

  @override
  void dispose() {
    _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewmodel,
      child: Column(children: [
        SimulatorCommandBar(),
        Expanded(child: SimulationList()),
      ]),
    );
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    showDialog(
        context: context,
        builder: (_) => SrxTheme(
            data: CustomTheme.srxTheme,
            child: SrxDialog.error(title: 'simulator.cannotstart.title'.tr(), bodyText: message)));
  }

  void _showStoppedByDisconnect() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('simulator.stoppeddisconnected.error'.tr(), context));
  }
}
