import Foundation
import RxSwift
import RxRelay
import RxCocoa

class ManageAccountViewModel {
    private let service: ManageAccountService
    private let accountRestoreWarningFactory: AccountRestoreWarningFactory
    private let disposeBag = DisposeBag()

    private let keyActionsRelay = BehaviorRelay<[[KeyAction]]>(value: [])
    private let showWarningRelay = BehaviorRelay<CancellableTitledCaution?>(value: nil)
    private let saveEnabledRelay = BehaviorRelay<Bool>(value: false)
    private let openUnlockRelay = PublishRelay<()>()
    private let openRecoveryPhraseRelay = PublishRelay<Account>()
    private let openBackupRelay = PublishRelay<Account>()
    private let openCloudBackupRelay = PublishRelay<Account>()
    private let confirmDeleteCloudBackupRelay = PublishRelay<Bool>()
    private let cloudBackupDeletedRelay = PublishRelay<Bool>()
    private let openUnlinkRelay = PublishRelay<Account>()
    private let finishRelay = PublishRelay<()>()

    private var unlockRequest: UnlockRequest = .recoveryPhrase

    init(service: ManageAccountService, accountRestoreWarningFactory: AccountRestoreWarningFactory) {
        self.service = service
        self.accountRestoreWarningFactory = accountRestoreWarningFactory

        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }
        subscribe(disposeBag, service.accountObservable) { [weak self] in self?.sync(account: $0) }
        subscribe(disposeBag, service.cloudBackedUpObservable) { [weak self] in self?.sync() }
        subscribe(disposeBag, service.accountDeletedObservable) { [weak self] in self?.finishRelay.accept(()) }

        sync(state: service.state)
        sync()
    }

    private func sync(state: ManageAccountService.State) {
        switch state {
        case .cannotSave: saveEnabledRelay.accept(false)
        case .canSave: saveEnabledRelay.accept(true)
        }
    }

    private func keyActions(account: Account, isCloudBackedUp: Bool) -> [[KeyAction]] {
        var backupActions = [KeyAction]()
        if !account.backedUp {
            backupActions.append(.backup(isCloudBackedUp: isCloudBackedUp))
        }

        backupActions.append(.cloudBackedUp(isCloudBackedUp, manualBackedUp: account.backedUp))

        guard account.backedUp || isCloudBackedUp else {
            return [backupActions]
        }

        var keyActions = [KeyAction]()
        switch account.type {
        case .mnemonic: keyActions.append(contentsOf: [.recoveryPhrase, .privateKeys, .publicKeys])
        case .evmPrivateKey: keyActions.append(contentsOf: [.privateKeys, .publicKeys])
        case .evmAddress: keyActions.append(contentsOf: [.publicKeys])
        case .hdExtendedKey(let key):
            switch key {
            case .private: keyActions.append(contentsOf: [.privateKeys, .publicKeys])
            case .public: keyActions.append(contentsOf: [.publicKeys])
            }
        }

        return [keyActions, backupActions]
    }

    private func sync(account: Account? = nil) {
        let account = account ?? service.account
        showWarningRelay.accept(accountRestoreWarningFactory.caution(account: account, canIgnoreActiveAccountWarning: false))
        keyActionsRelay.accept(keyActions(account: account, isCloudBackedUp: service.isCloudBackedUp))
    }

}

extension ManageAccountViewModel {

    var saveEnabledDriver: Driver<Bool> {
        saveEnabledRelay.asDriver()
    }

    var keyActionsDriver: Driver<[[KeyAction]]> {
        keyActionsRelay.asDriver()
    }

    var showWarningDriver: Driver<CancellableTitledCaution?> {
        showWarningRelay.asDriver()
    }

    var warningUrl: URL? {
        accountRestoreWarningFactory.warningUrl(account: service.account)
    }

    var openUnlockSignal: Signal<()> {
        openUnlockRelay.asSignal()
    }

    var openRecoveryPhraseSignal: Signal<Account> {
        openRecoveryPhraseRelay.asSignal()
    }

    var openBackupSignal: Signal<Account> {
        openBackupRelay.asSignal()
    }

    var openCloudBackupSignal: Signal<Account> {
        openCloudBackupRelay.asSignal()
    }

    var confirmDeleteCloudBackupSignal: Signal<Bool> {
        confirmDeleteCloudBackupRelay.asSignal()
    }

    var cloudBackupDeletedSignal: Signal<Bool> {
        cloudBackupDeletedRelay.asSignal()
    }

    var openUnlinkSignal: Signal<Account> {
        openUnlinkRelay.asSignal()
    }

    var finishSignal: Signal<()> {
        finishRelay.asSignal()
    }

    var accountName: String {
        service.account.name
    }

    var account: Account {
        service.account
    }

    func onUnlock() {
        switch unlockRequest {
        case .recoveryPhrase: openRecoveryPhraseRelay.accept(service.account)
        case .backup: openBackupRelay.accept(service.account)
        }
    }

    func onChange(name: String?) {
        service.set(name: name ?? "")
    }

    func onSave() {
        service.saveAccount()
        finishRelay.accept(())
    }

    func onTapRecoveryPhrase() {
        if service.isPinSet {
            unlockRequest = .recoveryPhrase
            openUnlockRelay.accept(())
        } else {
            openRecoveryPhraseRelay.accept(service.account)
        }
    }

    func onTapDeleteCloudBackup() {
        confirmDeleteCloudBackupRelay.accept(service.account.backedUp)
    }

    func deleteCloudBackup() {
        Task { [weak self] in
            do {
                try await service.deleteCloudBackup()
                self?.cloudBackupDeletedRelay.accept(true)
            } catch {
                self?.cloudBackupDeletedRelay.accept(false)
            }
        }
    }

    func deleteCloudBackupAfterManualBackup() {
        onTapBackup()
    }


    func onTapCloudBackup() {
        openCloudBackupRelay.accept(service.account)
    }

    func onTapBackup() {
        if service.isPinSet {
            unlockRequest = .backup
            openUnlockRelay.accept(())
        } else {
            openBackupRelay.accept(service.account)
        }
    }

    func onTapUnlink() {
        openUnlinkRelay.accept(service.account)
    }

}

extension ManageAccountViewModel {

    enum UnlockRequest {
        case recoveryPhrase
        case backup
    }

    enum KeyAction {
        case recoveryPhrase
        case publicKeys
        case privateKeys
        case backup(isCloudBackedUp: Bool)
        case cloudBackedUp(Bool, manualBackedUp: Bool)
    }

}
