#!/usr/bin/env python3
"""Reproducibly patch One UI 9.5 SystemUI.apk for QS smoothness & idle thermals (Phase 2).

Applies targeted smali edits (async layout constraint update, Compose debug log
off, RecompositionLogger bypass, QS blur radius 250/300 -> 110, hot Log.d removal,
and Nexus AnimatorCore 120Hz Choreographer leak fix on EdgeLighting hide/detach),
rebuilds classes*.dex via apktool, injects them into a verbatim copy of the stock
SystemUI.apk, runs zipalign -f -p 4, and transplants the original APK Sig Block 42.
"""

import argparse
import os
import shutil
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "staging" / "system" / "system_ext" / "priv-app" / "SystemUI" / "SystemUI.apk"
DEFAULT_ZIPALIGN = Path(
    os.environ.get(
        "ZIPALIGN",
        r"C:\Users\Gustyx-Power\AppData\Local\Android\Sdk\build-tools\36.0.0\zipalign.exe",
    )
)


def replace_once(path: Path, target: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(target)
    if count != 1:
        raise RuntimeError(f"{path.name}: expected 1 match for patch block, found {count}")
    path.write_text(text.replace(target, replacement, 1), encoding="utf-8", newline="\n")


def apply_smali_patches(smali_root: Path) -> None:
    # 1. Avoid synchronous requestLayout() during onLayout via View.post() on bounds change.
    replace_once(
        smali_root / "smali_classes3/com/android/systemui/shade/SecNotificationsQSContainerController$onInit$1.smali",
        """# virtual methods
.method public final onLayoutChange(Landroid/view/View;IIIIIIII)V
    .locals 0

    iget-object p0, p0, Lcom/android/systemui/shade/SecNotificationsQSContainerController$onInit$1;->this$0:Lcom/android/systemui/shade/SecNotificationsQSContainerController;

    iget-object p0, p0, Lcom/android/systemui/shade/SecNotificationsQSContainerController;->updateConstraints:Lkotlin/jvm/functions/Function0;

    invoke-interface {p0}, Lkotlin/jvm/functions/Function0;->invoke()Ljava/lang/Object;

    return-void
.end method""",
        """# virtual methods
.method public final onLayoutChange(Landroid/view/View;IIIIIIII)V
    .locals 1

    if-ne p2, p6, :cond_0

    if-ne p3, p7, :cond_0

    if-ne p4, p8, :cond_0

    if-eq p5, p9, :cond_1

    :cond_0
    if-eqz p1, :cond_1

    new-instance v0, Lcom/android/systemui/shade/SecNotificationsQSContainerController$onViewAttached$1;

    iget-object p0, p0, Lcom/android/systemui/shade/SecNotificationsQSContainerController$onInit$1;->this$0:Lcom/android/systemui/shade/SecNotificationsQSContainerController;

    invoke-direct {v0, p0}, Lcom/android/systemui/shade/SecNotificationsQSContainerController$onViewAttached$1;-><init>(Lcom/android/systemui/shade/SecNotificationsQSContainerController;)V

    invoke-virtual {p1, v0}, Landroid/view/View;->post(Ljava/lang/Runnable;)Z

    :cond_1
    return-void
.end method""",
    )

    # 2. Force QpRune.QUICK_PANEL_COMPOSE_DEBUG_LOG = false.
    replace_once(
        smali_root / "smali_classes4/com/android/systemui/QpRune.smali",
        """    sput-boolean v2, Lcom/android/systemui/QpRune;->QUICK_PANEL_COMPOSE:Z

    sput-boolean v2, Lcom/android/systemui/QpRune;->QUICK_PANEL_COMPOSE_DEBUG_LOG:Z

    sput-boolean v2, Lcom/android/systemui/QpRune;->QUICK_PANEL_COMPOSE_ICON_PERFORMANCE:Z""",
        """    sput-boolean v2, Lcom/android/systemui/QpRune;->QUICK_PANEL_COMPOSE:Z

    sput-boolean v5, Lcom/android/systemui/QpRune;->QUICK_PANEL_COMPOSE_DEBUG_LOG:Z

    sput-boolean v2, Lcom/android/systemui/QpRune;->QUICK_PANEL_COMPOSE_ICON_PERFORMANCE:Z""",
    )

    # 3. Skip RecompositionLoggerKt Log.isLoggable/SideEffect while keeping Compose groups.
    replace_once(
        smali_root / "smali_classes3/com/android/systemui/samsung/common/RecompositionLoggerKt.smali",
        "    :cond_c\n    if-eqz p2, :cond_11",
        "    :cond_c\n    goto :cond_11",
    )

    # 4. Reduce peak QS blur radius from 300/250 to smooth-glass 110.0f (0x42dc0000).
    color_curve = smali_root / "smali_classes2/com/android/systemui/blur/QSColorCurve.smali"
    replace_once(
        color_curve,
        "    sget-boolean p1, Lcom/android/systemui/QpRune;->QUICK_PANEL_BLUR_MASSIVE:Z\n\n    const/high16 v0, 0x43960000    # 300.0f",
        "    sget-boolean p1, Lcom/android/systemui/QpRune;->QUICK_PANEL_BLUR_MASSIVE:Z\n\n    const/high16 v0, 0x42dc0000    # 110.0f",
    )
    replace_once(
        color_curve,
        "    :cond_2\n    const/high16 v0, 0x437a0000    # 250.0f",
        "    :cond_2\n    const/high16 v0, 0x42dc0000    # 110.0f",
    )

    # 5-10. Remove per-frame unconditional Log.d + StringBuilder allocations.
    replace_once(
        smali_root / "smali_classes3/com/android/systemui/shade/PanelPopOverManager.smali",
        """    :cond_6
    :goto_1
    invoke-virtual {p0}, Lcom/android/systemui/shade/PanelPopOverManager;->getNeedToPopOver()Z

    move-result v0

    iget-boolean v3, p0, Lcom/android/systemui/shade/PanelPopOverManager;->isPopOverActive:Z

    check-cast v1, Lcom/android/systemui/keyguard/data/repository/KeyguardRepositoryImpl;

    iget-object v1, v1, Lcom/android/systemui/keyguard/data/repository/KeyguardRepositoryImpl;->statusBarState:Lkotlinx/coroutines/flow/ReadonlyStateFlow;

    iget-object v1, v1, Lkotlinx/coroutines/flow/ReadonlyStateFlow;->$$delegate_0:Lkotlinx/coroutines/flow/StateFlow;

    invoke-interface {v1}, Lkotlinx/coroutines/flow/StateFlow;->getValue()Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Lcom/android/systemui/keyguard/shared/model/StatusBarState;

    iget-byte p0, p0, Lcom/android/systemui/shade/PanelPopOverManager;->currentPanelState:B

    const-string v4, ", active="

    const-string v5, ", statusBarState="

    const-string/jumbo v6, "[QPDEX] activatePopOver skipped: need="

    invoke-static {v6, v4, v5, v0, v3}, Landroidx/compose/foundation/text/input/internal/TextFieldCoreModifier$$ExternalSyntheticOutline0;->m(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZZ)Ljava/lang/StringBuilder;

    move-result-object v0

    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    const-string v1, ", panelState="

    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object p0

    invoke-static {v2, p0}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    return-void
.end method""",
        """    :cond_6
    :goto_1
    return-void
.end method""",
    )

    replace_once(
        smali_root / "smali_classes2/com/android/systemui/blur/domain/interactor/SecPanelWindowBlurInteractor.smali",
        """    :goto_1
    iput v1, v4, Lcom/android/systemui/blur/data/repository/SecPanelWindowBlurRepository;->windowBlurRadius:I

    iget-object v1, v3, Lkotlinx/coroutines/flow/ReadonlyStateFlow;->$$delegate_0:Lkotlinx/coroutines/flow/StateFlow;

    invoke-interface {v1}, Lkotlinx/coroutines/flow/StateFlow;->getValue()Ljava/lang/Object;

    move-result-object v1

    iget-object p0, p0, Lcom/android/systemui/blur/domain/interactor/SecPanelWindowBlurInteractor;->secBlurSettingsInteractor:Lcom/android/systemui/blur/domain/interactor/SecBlurSettingsInteractor;

    iget-object p0, p0, Lcom/android/systemui/blur/domain/interactor/SecBlurSettingsInteractor;->blurReduced:Lkotlinx/coroutines/flow/ReadonlyStateFlow;

    iget-object p0, p0, Lkotlinx/coroutines/flow/ReadonlyStateFlow;->$$delegate_0:Lkotlinx/coroutines/flow/StateFlow;

    invoke-interface {p0}, Lkotlinx/coroutines/flow/StateFlow;->getValue()Ljava/lang/Object;

    move-result-object p0

    invoke-interface {v2}, Lkotlinx/coroutines/flow/StateFlow;->getValue()Ljava/lang/Object;

    move-result-object v2

    new-instance v3, Ljava/lang/StringBuilder;

    const-string/jumbo v4, "Window Blur:  "

    invoke-direct {v3, v4}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    invoke-virtual {v3, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string p1, "  shouldBlockBlur: "

    invoke-virtual {v3, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v3, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    const-string p1, " isBlurReduced: "

    invoke-virtual {v3, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v3, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    const-string p0, "  isBackgroundVisible: "

    invoke-virtual {v3, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object p0

    sget-object p1, Lcom/android/systemui/blur/domain/interactor/SecPanelWindowBlurInteractor;->TAG:Ljava/lang/String;

    invoke-static {p1, p0}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    return-object v0
.end method""",
        """    :goto_1
    iput v1, v4, Lcom/android/systemui/blur/data/repository/SecPanelWindowBlurRepository;->windowBlurRadius:I

    return-object v0
.end method""",
    )

    replace_once(
        smali_root / "smali_classes2/com/android/systemui/blur/ui/viewbinder/SecPanelBackgroundBinder.smali",
        """    :cond_4
    :goto_1
    iget-object p0, p0, Lcom/android/systemui/blur/ui/viewbinder/SecPanelBackgroundBinder;->viewModel:Lcom/android/systemui/blur/ui/viewmodel/SecPanelBackgroundViewModel;

    iget-object p0, p0, Lcom/android/systemui/blur/ui/viewmodel/SecPanelBackgroundViewModel;->maxAlpha:Lkotlinx/coroutines/flow/ReadonlyStateFlow;

    iget-object p0, p0, Lkotlinx/coroutines/flow/ReadonlyStateFlow;->$$delegate_0:Lkotlinx/coroutines/flow/StateFlow;

    invoke-interface {p0}, Lkotlinx/coroutines/flow/StateFlow;->getValue()Ljava/lang/Object;

    move-result-object p0

    check-cast p0, Ljava/lang/Number;

    invoke-virtual {p0}, Ljava/lang/Number;->floatValue()F

    move-result p0

    mul-float/2addr p0, p1

    const-string/jumbo p1, "setAlpha = "

    sget-object v0, Lcom/android/systemui/blur/ui/viewbinder/SecPanelBackgroundBinder;->TAG:Ljava/lang/String;

    invoke-static {p0, p1, v0}, Lcom/android/systemui/blur/SecQpBlurController$1$1$2$$ExternalSyntheticOutline0;->m(FLjava/lang/String;Ljava/lang/String;)V

    return-void
.end method""",
        """    :cond_4
    :goto_1
    return-void
.end method""",
    )

    replace_once(
        smali_root / "smali_classes2/com/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder.smali",
        """    :cond_5
    const-string p1, " translationY = "

    const-string v1, " panelTransition = "

    const-string/jumbo v3, "SecQSNewBlurView fraction = "

    invoke-static {v3, p1, v1, p0, v0}, Landroidx/compose/animation/CrossfadeKt$$ExternalSyntheticOutline0;->m(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;FF)Ljava/lang/StringBuilder;

    move-result-object p1

    sget-object v0, Lcom/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder;->TAG:Ljava/lang/String;

    invoke-static {p1, v2, v0}, Landroidx/appcompat/widget/SearchView$$ExternalSyntheticOutline0;->m(Ljava/lang/StringBuilder;ZLjava/lang/String;)V

    iget-object p1, p2, Lcom/android/systemui/blur/data/repository/SecPanelWindowBlurRepository;->qsColorCurve:Lcom/android/systemui/blur/QSColorCurve;""",
        """    :cond_5
    iget-object p1, p2, Lcom/android/systemui/blur/data/repository/SecPanelWindowBlurRepository;->qsColorCurve:Lcom/android/systemui/blur/QSColorCurve;""",
    )

    replace_once(
        smali_root / "smali_classes2/com/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder$1$1$1.smali",
        """    sget-object v1, Lcom/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder;->TAG:Ljava/lang/String;

    const-string/jumbo v3, "setBlurInfo "

    invoke-static {v0, v3, v1}, Landroidx/appcompat/widget/SearchView$$ExternalSyntheticOutline0;->m(ILjava/lang/String;Ljava/lang/String;)V

    sget-boolean v0, Lcom/android/systemui/QpRune;->QUICK_PANEL_CODE_FOR_POP_OVER:Z""",
        "    sget-boolean v0, Lcom/android/systemui/QpRune;->QUICK_PANEL_CODE_FOR_POP_OVER:Z",
    )

    replace_once(
        smali_root / "smali_classes2/com/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder$1$1$2.smali",
        """    if-lez p1, :cond_1

    sget-object p1, Lcom/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder;->TAG:Ljava/lang/String;

    const-string/jumbo v1, "shouldBlockWindowBlur "

    invoke-static {v1, p1, v0}, Lcom/android/bouncer/ui/composable/externalbouncer/ExternalWindowBouncerKt$$ExternalSyntheticOutline0;->m(Ljava/lang/String;Ljava/lang/String;Z)V

    iget-object p0, p0, Lcom/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder$1$1$2;->this$0:Lcom/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder;""",
        """    if-lez p1, :cond_1

    iget-object p0, p0, Lcom/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder$1$1$2;->this$0:Lcom/android/systemui/blur/ui/viewbinder/SecPanelWindowBlurBinder;""",
    )

    # 11. Strip 4 Log.d + StringBuilder blocks in QuickTileBoxKt$Lambda4 (keep v46 + Compose calls).
    tile_box = smali_root / "smali_classes3/com/android/systemui/samsung/quicksetting/ui/tiles/QuickTileBoxKt$$ExternalSyntheticLambda4.smali"
    replace_once(
        tile_box,
        """    move-object/from16 v40, v6

    new-instance v6, Ljava/lang/StringBuilder;

    move/from16 v46, v0

    const-string/jumbo v0, "updateItemHeightAndPadding H="

    invoke-direct {v6, v0}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    invoke-virtual {v6, v15}, Ljava/lang/StringBuilder;->append(F)Ljava/lang/StringBuilder;

    const-string v0, " rows="

    invoke-virtual {v6, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v6, v5}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string v0, " minH="

    invoke-virtual {v6, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v0, " padTargetPx="

    const-string v5, " slack="

    invoke-static {v6, v13, v0, v11, v5}, Landroidx/compose/animation/core/Motion$$ExternalSyntheticOutline0;->m(Ljava/lang/StringBuilder;FLjava/lang/String;FLjava/lang/String;)V

    invoke-virtual {v6, v10}, Ljava/lang/StringBuilder;->append(F)Ljava/lang/StringBuilder;

    const-string v0, " slice="

    invoke-virtual {v6, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v6, v14}, Ljava/lang/StringBuilder;->append(F)Ljava/lang/StringBuilder;

    invoke-virtual {v6}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    const-string/jumbo v5, "QuickTileBox"

    invoke-static {v5, v0}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    cmpg-float v0, v10, v39""",
        """    move-object/from16 v40, v6

    move/from16 v46, v0

    cmpg-float v0, v10, v39""",
    )
    replace_once(
        tile_box,
        """    invoke-static {v0, v6, v7}, Lcom/android/systemui/media/mediaoutput/compose/widget/AudioVisSeekbarDefaults;->toPx-8Feqmps(FILandroidx/compose/runtime/Composer;)F

    move-result v0

    new-instance v6, Ljava/lang/StringBuilder;

    const-string/jumbo v10, "updateItemHeightAndPadding shortage pad="

    invoke-direct {v6, v10}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    invoke-virtual {v6, v0}, Ljava/lang/StringBuilder;->append(F)Ljava/lang/StringBuilder;

    invoke-virtual {v6}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    invoke-static {v5, v0}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    invoke-interface {v7}, Landroidx/compose/runtime/Composer;->endReplaceGroup()V""",
        """    invoke-static {v0, v6, v7}, Lcom/android/systemui/media/mediaoutput/compose/widget/AudioVisSeekbarDefaults;->toPx-8Feqmps(FILandroidx/compose/runtime/Composer;)F

    invoke-interface {v7}, Landroidx/compose/runtime/Composer;->endReplaceGroup()V""",
    )
    replace_once(
        tile_box,
        """    invoke-static {v0, v6, v7}, Lcom/android/systemui/media/mediaoutput/compose/widget/AudioVisSeekbarDefaults;->toPx-8Feqmps(FILandroidx/compose/runtime/Composer;)F

    move-result v0

    new-instance v6, Ljava/lang/StringBuilder;

    const-string/jumbo v10, "updateItemHeightAndPadding split pad="

    invoke-direct {v6, v10}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    invoke-virtual {v6, v0}, Ljava/lang/StringBuilder;->append(F)Ljava/lang/StringBuilder;

    invoke-virtual {v6}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    invoke-static {v5, v0}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    add-float/2addr v13, v14""",
        """    invoke-static {v0, v6, v7}, Lcom/android/systemui/media/mediaoutput/compose/widget/AudioVisSeekbarDefaults;->toPx-8Feqmps(FILandroidx/compose/runtime/Composer;)F

    add-float/2addr v13, v14""",
    )
    replace_once(
        tile_box,
        """    iput v12, v1, Lkotlin/jvm/internal/Ref$FloatRef;->element:F

    new-instance v0, Ljava/lang/StringBuilder;

    const-string/jumbo v6, "updateItemHeightAndPadding boxPad itemH="

    invoke-direct {v0, v6}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    invoke-virtual {v0, v13}, Ljava/lang/StringBuilder;->append(F)Ljava/lang/StringBuilder;

    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    invoke-static {v5, v0}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I

    invoke-static {}, Landroidx/compose/runtime/ComposerKt;->isTraceInProgress()Z""",
        """    iput v12, v1, Lkotlin/jvm/internal/Ref$FloatRef;->element:F

    invoke-static {}, Landroidx/compose/runtime/ComposerKt;->isTraceInProgress()Z""",
    )

    # 11. Stop Samsung Nexus AnimatorCore 120Hz Choreographer loop when EdgeLighting+ hides or detaches.
    replace_once(
        smali_root / "smali_classes5/com/samsung/android/nexus/base/animator/AnimatorCore$1.smali",
        """    iget-object v0, p0, Lcom/samsung/android/nexus/base/animator/AnimatorCore$1;->this$0:Lcom/samsung/android/nexus/base/animator/AnimatorCore;

    iget-wide v1, v0, Lcom/samsung/android/nexus/base/animator/AnimatorCore;->mFrameStartTime:J""",
        """    iget-object v0, p0, Lcom/samsung/android/nexus/base/animator/AnimatorCore$1;->this$0:Lcom/samsung/android/nexus/base/animator/AnimatorCore;

    iget-byte v1, v0, Lcom/samsung/android/nexus/base/animator/AnimatorCore;->mRenderMode:B

    if-nez v1, :cond_render

    return-void

    :cond_render
    iget-wide v1, v0, Lcom/samsung/android/nexus/base/animator/AnimatorCore;->mFrameStartTime:J""",
    )
    replace_once(
        smali_root / "smali_classes5/com/samsung/android/nexus/base/animator/AnimatorCore.smali",
        """    iget-object v0, p0, Lcom/samsung/android/nexus/base/animator/AnimatorCore;->mChoreographer:Landroid/view/Choreographer;

    invoke-virtual {v0, v1}, Landroid/view/Choreographer;->removeFrameCallback(Landroid/view/Choreographer$FrameCallback;)V

    iget-object p0, p0, Lcom/samsung/android/nexus/base/animator/AnimatorCore;->mChoreographer:Landroid/view/Choreographer;

    invoke-virtual {p0, v1}, Landroid/view/Choreographer;->postFrameCallback(Landroid/view/Choreographer$FrameCallback;)V

    return-void""",
        """    iget-object v0, p0, Lcom/samsung/android/nexus/base/animator/AnimatorCore;->mChoreographer:Landroid/view/Choreographer;

    invoke-virtual {v0, v1}, Landroid/view/Choreographer;->removeFrameCallback(Landroid/view/Choreographer$FrameCallback;)V

    iget-byte v0, p0, Lcom/samsung/android/nexus/base/animator/AnimatorCore;->mRenderMode:B

    if-eqz v0, :cond_stop

    iget-object p0, p0, Lcom/samsung/android/nexus/base/animator/AnimatorCore;->mChoreographer:Landroid/view/Choreographer;

    invoke-virtual {p0, v1}, Landroid/view/Choreographer;->postFrameCallback(Landroid/view/Choreographer$FrameCallback;)V

    :cond_stop
    return-void""",
    )
    replace_once(
        smali_root / "smali_classes5/com/samsung/android/nexus/base/layer/LayerContainer.smali",
        """    const-string v0, "LayerContainer"

    const-string/jumbo v1, "destroy()"

    invoke-static {v0, v1}, Lcom/samsung/android/nexus/base/utils/Log;->i(Ljava/lang/String;Ljava/lang/String;)V

    iget-object p0, p0, Lcom/samsung/android/nexus/base/layer/LayerContainer;->mEffectLayer:Ljava/util/List;""",
        """    const-string v0, "LayerContainer"

    const-string/jumbo v1, "destroy()"

    invoke-static {v0, v1}, Lcom/samsung/android/nexus/base/utils/Log;->i(Ljava/lang/String;Ljava/lang/String;)V

    const/4 v0, 0x0

    invoke-virtual {p0, v0}, Lcom/samsung/android/nexus/base/layer/LayerContainer;->setRenderMode(I)V

    iget-object p0, p0, Lcom/samsung/android/nexus/base/layer/LayerContainer;->mEffectLayer:Ljava/util/List;""",
    )
    emitter_view = smali_root / "smali_classes5/com/samsung/android/nexus/particle/emitter/view/ParticleEmitterView.smali"
    replace_once(
        emitter_view,
        """    const-string v0, "LayerContainer"

    invoke-static {v0, p2}, Lcom/samsung/android/nexus/base/utils/Log;->i(Ljava/lang/String;Ljava/lang/String;)V

    invoke-virtual {p0, p1}, Lcom/samsung/android/nexus/base/layer/LayerContainer;->onVisibilityChanged(Ljava/lang/Boolean;)V

    :cond_1
    return-void
.end method

.method public final onWindowVisibilityChanged(I)V""",
        """    const-string v0, "LayerContainer"

    invoke-static {v0, p2}, Lcom/samsung/android/nexus/base/utils/Log;->i(Ljava/lang/String;Ljava/lang/String;)V

    invoke-virtual {p0, p1}, Lcom/samsung/android/nexus/base/layer/LayerContainer;->onVisibilityChanged(Ljava/lang/Boolean;)V

    if-nez p2, :cond_hide_mode

    const/4 p1, 0x2

    goto :goto_mode

    :cond_hide_mode
    const/4 p1, 0x0

    :goto_mode
    invoke-virtual {p0, p1}, Lcom/samsung/android/nexus/base/layer/LayerContainer;->setRenderMode(I)V

    :cond_1
    return-void
.end method

.method public final onWindowVisibilityChanged(I)V""",
    )
    replace_once(
        emitter_view,
        """    const-string v1, "LayerContainer"

    invoke-static {v1, v0}, Lcom/samsung/android/nexus/base/utils/Log;->i(Ljava/lang/String;Ljava/lang/String;)V

    invoke-virtual {p0, p1}, Lcom/samsung/android/nexus/base/layer/LayerContainer;->onVisibilityChanged(Ljava/lang/Boolean;)V

    :cond_1
    return-void
.end method""",
        """    const-string v1, "LayerContainer"

    invoke-static {v1, v0}, Lcom/samsung/android/nexus/base/utils/Log;->i(Ljava/lang/String;Ljava/lang/String;)V

    invoke-virtual {p0, p1}, Lcom/samsung/android/nexus/base/layer/LayerContainer;->onVisibilityChanged(Ljava/lang/Boolean;)V

    invoke-virtual {p1}, Ljava/lang/Boolean;->booleanValue()Z

    move-result v0

    if-eqz v0, :cond_win_hide

    const/4 v0, 0x2

    goto :goto_win_mode

    :cond_win_hide
    const/4 v0, 0x0

    :goto_win_mode
    invoke-virtual {p0, v0}, Lcom/samsung/android/nexus/base/layer/LayerContainer;->setRenderMode(I)V

    :cond_1
    return-void
.end method""",
    )


def inject_sig_block(orig_apk: Path, aligned_apk: Path, out_apk: Path) -> None:
    odata = orig_apk.read_bytes()
    oeocd = odata.rfind(b"PK\x05\x06")
    ocd_offset = struct.unpack_from("<I", odata, oeocd + 16)[0]
    osig_size = struct.unpack_from("<Q", odata, ocd_offset - 24)[0]
    sig_block = odata[ocd_offset - 8 - osig_size : ocd_offset]
    if sig_block[-16:] != b"APK Sig Block 42":
        raise ValueError("Original APK missing APK Sig Block 42")

    sdata = aligned_apk.read_bytes()
    seocd = sdata.rfind(b"PK\x05\x06")
    scd_size, scd_offset = struct.unpack_from("<II", sdata, seocd + 12)
    if scd_offset + scd_size != seocd:
        raise ValueError("Aligned APK has unexpected ZIP trailer")

    pad_len = (4096 - (scd_offset % 4096)) % 4096
    new_cd_offset = scd_offset + pad_len + len(sig_block)
    new_eocd = bytearray(sdata[seocd:])
    struct.pack_into("<I", new_eocd, 16, new_cd_offset)

    out_apk.parent.mkdir(parents=True, exist_ok=True)
    with out_apk.open("wb") as f:
        f.write(sdata[:scd_offset])
        if pad_len:
            f.write(b"\x00" * pad_len)
        f.write(sig_block)
        f.write(sdata[scd_offset:seocd])
        f.write(new_eocd)


def main() -> None:
    parser = argparse.ArgumentParser(description="Patch One UI 9.5 SystemUI.apk for QS smoothness")
    parser.add_argument("input_apk", type=Path, help="Path to stock SystemUI.apk")
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_OUT, help="Patched output APK path")
    parser.add_argument("--zipalign", type=Path, default=DEFAULT_ZIPALIGN, help="Path to zipalign binary")
    args = parser.parse_args()

    apktool_cmd = shutil.which("apktool")
    if not apktool_cmd:
        raise SystemExit("apktool not found on PATH")
    if not args.zipalign.is_file():
        raise SystemExit(f"zipalign not found at {args.zipalign}")

    with tempfile.TemporaryDirectory(prefix="sysui_qs_") as td:
        tmp = Path(td)
        decoded = tmp / "decoded"
        rebuilt = tmp / "rebuilt.apk"
        unaligned = tmp / "unaligned.apk"
        aligned = tmp / "aligned.apk"

        subprocess.run([apktool_cmd, "d", "-f", "-r", str(args.input_apk), "-o", str(decoded)], check=True)
        apply_smali_patches(decoded)
        subprocess.run([apktool_cmd, "b", str(decoded), "-o", str(rebuilt)], check=True)

        with zipfile.ZipFile(args.input_apk, "r") as z_orig, \
             zipfile.ZipFile(rebuilt, "r") as z_built, \
             zipfile.ZipFile(unaligned, "w") as z_out:
            for info in z_orig.infolist():
                if info.filename.startswith("classes") and info.filename.endswith(".dex"):
                    continue
                zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                zi.compress_type = info.compress_type
                zi.external_attr = info.external_attr
                z_out.writestr(zi, z_orig.read(info.filename), compress_type=info.compress_type)
            for info in z_built.infolist():
                if info.filename.startswith("classes") and info.filename.endswith(".dex"):
                    zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                    zi.compress_type = zipfile.ZIP_STORED
                    z_out.writestr(zi, z_built.read(info.filename), compress_type=zipfile.ZIP_STORED)

        subprocess.run([str(args.zipalign), "-f", "-p", "4", str(unaligned), str(aligned)], check=True)
        inject_sig_block(args.input_apk, aligned, args.output)
        subprocess.run([str(args.zipalign), "-c", "-p", "-v", "4", str(args.output)], check=True)
        print(f"[OK] Built patched APK: {args.output} ({args.output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
