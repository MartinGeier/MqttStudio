import 'dart:async';
import 'package:dio/dio.dart';
import 'package:srx_flutter/src/controller/srx_session_controller.dart';
import '../service/srx_service_error.dart';
import '../service/srx_service_exception.dart';
import 'package:flutter/foundation.dart' as Foundation;

class SrxHttpService {
  final String baseUrlRelease;
  final String baseUrlDebug;
  final String versionPath;
  final SrxSessionController sessionController;

  Dio _dio;

  SrxHttpService(this.baseUrlRelease, this.baseUrlDebug, this.versionPath, this.sessionController) : _dio = Dio() {
    _dio.options.connectTimeout = 10000;
    _dio.interceptors.add(InterceptorsWrapper(onRequest: onRequestInterceptor));
  }

  Future<Response<T>> get<T>(String urlPath) async {
    try {
      var url = '${getBaseUrl()}/$versionPath/$urlPath';
      return await _dio.get(url);
    } on DioError catch (err) {
      throw _getException(err);
    }
  }

  Future<Response<T>> post<T>(String urlPath, {dynamic data}) async {
    try {
      var url = '${getBaseUrl()}/$versionPath/$urlPath';
      return await _dio.post<T>(url, data: data);
    } on DioError catch (err) {
      throw _getException(err);
    }
  }

  Future delete<T>(String urlPath) async {
    try {
      var url = '${getBaseUrl()}/$versionPath/$urlPath';
      await _dio.delete<T>(url);
    } on DioError catch (err) {
      throw _getException(err);
    }
  }

  Future<Response<T>> put<T>(String urlPath, dynamic data) async {
    try {
      var url = '${getBaseUrl()}/$versionPath/$urlPath';
      return await _dio.put<T>(url, data: data);
    } on DioError catch (err) {
      throw _getException(err);
    }
  }

  Future<SrxToken> getToken(String username, String password) async {
    try {
      var response = await post(
        'authentication/token',
        data: {
          "granttype": 'ResourceOwnerPassword',
          "clientid": "EnerdeskClient",
          "clientsecret": "rgashkdlsas545s1sdfsdffvcvcnjhgj.284",
          "login": username,
          "password": password,
        },
      );

      if (response.statusCode == 200) {
        return SrxToken(response.data["accessToken"], response.data["refreshToken"], response.data["accessTokenExpiresInSecs"]);
      } else {
        throw SrxServiceException(response.data, SrxServiceError.Unknown);
      }
    } on SrxServiceException catch (exc) {
      if (exc.serviceError == SrxServiceError.BadRequest) {
        throw SrxServiceException(exc.errorMessage, SrxServiceError.InvalidCredentials);
      } else {
        throw exc;
      }
    }
  }

  Future<bool> refreshToken() async {
    if (sessionController.session == null) {
      throw new Exception('Cannot renew access token without a valid session');
    }

    try {
      var response = await post(
        'authentication/refresh',
        data: {
          "refreshToken": sessionController.session?.refreshToken,
        },
      );

      if (response.statusCode == 200) {
        sessionController.session
            ?.setToken(SrxToken(response.data["accessToken"], response.data["refreshToken"], response.data["accessTokenExpiresInSecs"]));
        return true;
      } else {
        throw SrxServiceException(response.data, SrxServiceError.Unknown);
      }
    } on SrxServiceException catch (exc) {
      if (exc.serviceError != SrxServiceError.NoConnection) {
        sessionController.logout();
      } else {
        throw exc;
      }
      return false;
    }
  }

  String getBaseUrl() {
    return Foundation.kReleaseMode ? baseUrlRelease : baseUrlDebug;
  }

  void onRequestInterceptor(RequestOptions options, RequestInterceptorHandler handler) async {
    var session = sessionController.session;

    // if this is a token request just continue
    if (options.path.endsWith('authentication/token') || options.path.endsWith('authentication/refresh')) {
      return handler.next(options);
    }

    // if we have no session we cannot continue
    if (session == null) {
      return handler.reject(DioError(requestOptions: options));
    }

    // if the access token has expired try to get a new one using the refresh token
    if (DateTime.now().isAfter(session.accessTokenExpirationDateTime)) {
      try {
        if (!await refreshToken()) {
          // if we cannot refresh the access token just fail
          return handler.reject(DioError(requestOptions: options, type: DioErrorType.cancel));
        }
      } on SrxServiceException {
        return handler.reject(DioError(requestOptions: options, type: DioErrorType.cancel));
      }
    }

    // everything looks good, add the access token and proceed...
    options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    return handler.next(options);
  }

  Exception _getException(DioError err) {
    if (err.type == DioErrorType.connectTimeout || err.type == DioErrorType.cancel) {
      return SrxServiceException(err.message, SrxServiceError.NoConnection);
    } else if (err.response?.statusCode == 400) {
      return SrxServiceException(err.message, SrxServiceError.BadRequest);
    } else if (err.response?.statusCode == 403) {
      return SrxServiceException(err.message, SrxServiceError.Forbidden);
    } else if (err.response?.statusCode == 404) {
      return SrxServiceException(err.message, SrxServiceError.NotFound);
    } else if (err.response?.statusCode == 409) {
      return SrxServiceException(err.message, SrxServiceError.Conflict);
    } else {
      return SrxServiceException(err.message, SrxServiceError.Unknown);
    }
  }
}

class SrxToken {
  String accessToken;
  String refreshToken;
  int accessTokenExpirationTime;

  SrxToken(this.accessToken, this.refreshToken, this.accessTokenExpirationTime);
}
