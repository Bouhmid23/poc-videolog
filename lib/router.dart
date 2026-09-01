import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import 'presentation/screens/connect.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/room.dart';
import 'presentation/screens/rooms_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final goRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/home/:username',
      builder: (context, state) => HomeScreen(
        username: state.pathParameters['username']!,
      ),
    ),
    GoRoute(
      path: '/rooms/:username',
      builder: (context, state) => RoomsScreen(
        username: state.pathParameters['username']!,
      ),
    ),
    GoRoute(
      path: '/connect/:roomName',
      builder: (context, state) => ConnectPage(
        roomName: state.pathParameters['roomName']!,
        initialUsername: state.extra as String?,
      ),
    ),
    // PreJoin & Room are pushed on top of the stack via context.push()
    GoRoute(
      path: '/prejoin',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => PreJoinPage(
        args: state.extra as JoinArgs,
      ),
    ),
    GoRoute(
      path: '/room',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final args = state.extra as (Room, EventsListener<RoomEvent>);
        return RoomPage(args.$1, args.$2, fastConnection: true);
      },
    ),
  ],
);
