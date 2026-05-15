function Controller() {
    installer.setMessageBoxAutomaticAnswer("OverwriteTargetDirectory", QMessageBox.Yes);
    installer.setMessageBoxAutomaticAnswer("installationErrorWithRetry", QMessageBox.Ignore);
}

Controller.prototype.IntroductionPageCallback = function() {
    gui.clickButton(buttons.NextButton);
}

Controller.prototype.TargetDirectoryPageCallback = function() {
    gui.currentPageWidget().TargetDirectoryLineEdit.setText("/opt/QtSDK");
    gui.clickButton(buttons.NextButton);
}

Controller.prototype.ComponentSelectionPageCallback = function() {
    var widget = gui.currentPageWidget();

    // Deselect everything we don't need for headless cross-compile builds
    widget.deselectAll();

    // Then select only what we need
    widget.selectComponent("com.nokia.ndk.tools.madde.application");
    widget.selectComponent("com.nokia.ndk.tools.madde.toolchains.2009q367");
    widget.selectComponent("com.nokia.ndk.tools.madde.qttools.474");
    widget.selectComponent("com.nokia.ndk.tools.harmattan.sysroot");
    widget.selectComponent("com.nokia.ndk.tools.harmattan.qtcomponents");

    gui.clickButton(buttons.NextButton);
}

Controller.prototype.LicenseAgreementPageCallback = function() {
    gui.currentPageWidget().AcceptLicenseRadioButton.setChecked(true);
    gui.clickButton(buttons.NextButton);
}

Controller.prototype.ReadyForInstallationPageCallback = function() {
    gui.clickButton(buttons.NextButton);
}

Controller.prototype.FinishedPageCallback = function() {
    gui.clickButton(buttons.FinishButton);
}
