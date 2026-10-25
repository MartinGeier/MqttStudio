// What can be done to a running simulated robot (doc/vda5050-design.md §10.4). Faults are runtime state and reset on
// every start (simulator D28).
enum RobotFaultGroup { robot, connection, protocol }

enum RobotFault {
  warning(RobotFaultGroup.robot),
  urgent(RobotFaultGroup.robot, v3Only: true),
  critical(RobotFaultGroup.robot, v3Only: true),
  fatal(RobotFaultGroup.robot),
  emergencyStop(RobotFaultGroup.robot, toggle: true),
  fieldViolation(RobotFaultGroup.robot, toggle: true),
  pause(RobotFaultGroup.robot, toggle: true),
  lowBattery(RobotFaultGroup.robot),
  cancelOrder(RobotFaultGroup.robot),
  clearErrors(RobotFaultGroup.robot),
  connectionBroken(RobotFaultGroup.connection),
  offline(RobotFaultGroup.connection),
  hibernate(RobotFaultGroup.connection, v3Only: true),
  reconnect(RobotFaultGroup.connection),
  skipHeaderIds(RobotFaultGroup.protocol),
  clockSkew(RobotFaultGroup.protocol, toggle: true),
  wrongSerialNumber(RobotFaultGroup.protocol, toggle: true),
  brokenOrder(RobotFaultGroup.protocol),
  lowerOrderUpdate(RobotFaultGroup.protocol),
  responseWithoutRequest(RobotFaultGroup.protocol, v3Only: true),
  unansweredRequest(RobotFaultGroup.protocol, v3Only: true);

  final RobotFaultGroup group;
  // only for robots that speak VDA 5050 3.0
  final bool v3Only;
  // switched on and off; the others act once
  final bool toggle;

  const RobotFault(this.group, {this.v3Only = false, this.toggle = false});
}
