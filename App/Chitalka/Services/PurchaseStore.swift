import Foundation
import StoreKit

/// Покупка премиума. StoreKit 2, разовая покупка, £4.99.
///
/// Подписки нет намеренно: при таком чеке отмены и возвраты съедают разницу.
///
/// Проверка владения работает офлайн: `Transaction.currentEntitlements` читает
/// подписанные транзакции из локального хранилища и проверяет подпись ключом Apple.
/// Сеть нужна ровно в двух местах — сама покупка и «Восстановить покупки».
@Observable
final class PurchaseStore {

    /// Должен совпасть с идентификатором в App Store Connect.
    static let premiumProductID = "com.chitalka.premium"

    private(set) var product: Product?
    private(set) var isPurchased = false
    private(set) var isWorking = false
    private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    /// Цена так, как её показывает App Store в валюте пользователя.
    /// Хардкодить «£4.99» нельзя: в других странах цена другая.
    var displayPrice: String { product?.displayPrice ?? "£4.99" }

    init() {
        // Транзакции приходят и вне покупки: Ask to Buy, возврат, покупка
        // на другом устройстве. Слушать надо всегда, пока приложение живо.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self.refresh()
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    @MainActor
    func load() async {
        do {
            product = try await Product.products(for: [Self.premiumProductID]).first
        } catch {
            lastError = "Не удалось загрузить цену. Проверьте соединение."
        }
        await refresh()
    }

    @MainActor
    func refresh() async {
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.premiumProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        isPurchased = owned
    }

    @MainActor
    func purchase() async {
        guard let product else {
            lastError = "Товар недоступен. Попробуйте позже."
            return
        }
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refresh()
                } else {
                    lastError = "Покупку не удалось подтвердить."
                }
            case .userCancelled:
                break
            case .pending:
                lastError = "Покупка ждёт подтверждения."
            @unknown default:
                break
            }
        } catch {
            lastError = "Покупка не прошла. Попробуйте ещё раз."
        }
    }

    /// Обязательна по правилам App Store: без этой кнопки приложение не пройдёт ревью.
    @MainActor
    func restore() async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            try await AppStore.sync()
            await refresh()
            if !isPurchased {
                lastError = "Покупок для этого Apple ID не найдено."
            }
        } catch {
            lastError = "Не удалось связаться с App Store. Нужно соединение."
        }
    }
}
