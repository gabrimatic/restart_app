/*
 * Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import common from '@ohos.app.ability.common'
import { Want } from '@kit.AbilityKit'

export const TAG = 'MethodCallHandlerImpl';

export default class MethodCallHandlerImpl implements MethodCallHandler {
  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.i(TAG, "onMethodCall  method:" + call.method);
    switch (call.method) {
      case 'restartApp': {
        let context = getContext(this) as common.UIAbilityContext
        let bundleName = context.abilityInfo.bundleName
        context.terminateSelf(() => {
          let want: Want = {
            bundleName: bundleName,
            abilityName: "EntryAbility"
          }
          context.startAbility(want);
        })
        result.success('ok');
        break;
      }
      default: {
        result.notImplemented();
      }
    }
  }
}