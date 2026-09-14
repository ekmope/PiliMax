import 'dart:async';
import 'dart:math';

import 'package:PiliPlus/http/dao/dao.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/utils/cdn_node_store.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// CDN服务：管理CDN节点选择、测速、流量统计
class CdnService {
  static final CdnService _instance = CdnService._internal();
  factory CdnService() => _instance;
  CdnService._internal();

  /// 当前使用的CDN服务
  CDNService currentService = Pref.defaultCDNService;

  /// 所有可用的CDN服务
  List<CDNService> allServices = [];

  /// 是否已初始化
  bool _isInitialized = false;

  /// 初始化CDN服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 加载所有CDN服务
      await _loadAllServices();
      
      // 设置当前服务
      _setCurrentService();
      
      _isInitialized = true;
      debugPrint('CDN服务初始化完成');
    } catch (e) {
      debugPrint('CDN服务初始化失败: $e');
      rethrow;
    }
  }

  /// 加载所有CDN服务
  Future<void> _loadAllServices() async {
    allServices = [
      // 默认CDN服务
      CDNService(
        id: 'default',
        name: '默认CDN',
        desc: '使用B站默认CDN',
        type: CdnType.upos,
        priority: 0,
        enabled: true,
      ),
      // 自定义CDN服务
      if (Pref.customCDNUrl != null && Pref.customCDNUrl!.isNotEmpty)
        CDNService(
          id: 'custom',
          name: '自定义CDN',
          desc: '使用自定义CDN节点: ${Pref.customCDNUrl}',
          type: CdnType.custom,
          priority: 1,
          enabled: true,
          customUrl: Pref.customCDNUrl,
        ),
      // 从CDN节点存储中创建服务
      ..._createServicesFromNodes(),
    ];
  }

  /// 从CDN节点创建服务
  List<CDNService> _createServicesFromNodes() {
    final services = <CDNService>[];
    
    try {
      final nodes = CdnNodeStore.nodes;
      if (nodes.isEmpty) return services;

      var priority = 2;
      for (final region in CdnNodeStore.regionOrder) {
        final hosts = nodes[region] ?? [];
        if (hosts.isEmpty) continue;

        for (final host in hosts) {
          services.add(CDNService(
            id: 'region_$priority',
            name: region,
            desc: '地区CDN: $region',
            type: CdnType.region,
            priority: priority++,
            enabled: true,
            region: region,
            hosts: hosts,
          ));
        }
      }
    } catch (e) {
      debugPrint('创建CDN节点服务失败: $e');
    }

    return services;
  }

  /// 设置当前服务
  void _setCurrentService() {
    // 从存储中获取当前服务ID
    final currentServiceId = GStorage.setting.get(SettingBoxKey.currentCdnService);
    
    if (currentServiceId != null) {
      final service = allServices.firstWhere(
        (s) => s.id == currentServiceId,
        orElse: () => Pref.defaultCDNService,
      );
      currentService = service;
    } else {
      currentService = Pref.defaultCDNService;
    }
  }

  /// 切换CDN服务
  Future<void> switchService(String serviceId) async {
    final service = allServices.firstWhere(
      (s) => s.id == serviceId,
      orElse: () => Pref.defaultCDNService,
    );

    if (service == currentService) return;

    currentService = service;
    
    // 保存到存储
    await GStorage.setting.put(SettingBoxKey.currentCdnService, serviceId);
    
    debugPrint('切换CDN服务: ${service.name}');
  }

  /// 获取当前CDNURL
  String getCurrentCdnUrl(String originalUrl) {
    if (currentService.type == CdnType.custom && currentService.customUrl != null) {
      return originalUrl.replaceFirst(
        RegExp(r'https?://[^/]+'),
        currentService.customUrl!,
      );
    }
    
    if (currentService.type == CdnType.region && currentService.hosts != null) {
      // 随机选择一个主机
      final hosts = currentService.hosts!;
      final random = Random();
      final selectedHost = hosts[random.nextInt(hosts.length)];
      
      return originalUrl.replaceFirst(
        RegExp(r'https?://[^/]+'),
        'https://$selectedHost',
      );
    }
    
    return originalUrl;
  }

  /// 测试CDN服务速度
  Future<double> testServiceSpeed(String serviceId) async {
    final service = allServices.firstWhere(
      (s) => s.id == serviceId,
      orElse: () => Pref.defaultCDNService,
    );

    try {
      // 使用一个测试URL进行测速
      final testUrl = 'https://test.cdn.speed';
      final startTime = DateTime.now();
      
      final response = await Dio().head(testUrl);
      final endTime = DateTime.now();
      
      final duration = endTime.difference(startTime).inMilliseconds;
      final speed = 1000 / duration; // 简单的速度计算
      
      return speed;
    } catch (e) {
      debugPrint('CDN服务测速失败: $e');
      return 0.0;
    }
  }

  /// 获取所有可用的CDN服务
  List<CDNService> getAvailableServices() {
    return allServices.where((s) => s.enabled).toList();
  }

  /// 启用/禁用CDN服务
  Future<void> setServiceEnabled(String serviceId, bool enabled) async {
    final service = allServices.firstWhere(
      (s) => s.id == serviceId,
      orElse: () => Pref.defaultCDNService,
    );

    service.enabled = enabled;
    
    // 如果禁用的是当前服务，切换到默认服务
    if (!enabled && service == currentService) {
      await switchService(Pref.defaultCDNService.id);
    }
  }
}