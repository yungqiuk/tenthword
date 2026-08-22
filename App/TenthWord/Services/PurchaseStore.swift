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
    static let premiumProductID = "com.tenthword.premium"

    private(set) var product: Product?
    private(set) var isPurchased = false
    private(set) var isWorking = false
    private(set) var isLoadingProduct = false
    private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    /// Цена так, как её показывает App Store в валюте и формате пользователя.
    ///
    /// Запасного значения здесь нет намеренно. Цену назначает App Store Connect:
    /// в каждой стране она своя, Apple меняет её вслед за курсом, а в России
    /// покупки вообще недоступны. Показать «£4.99» тому, у кого спишется 990 ₽
    /// или ¥800, — это и обман, и отказ на ревью. Пока товар не загружен, цены
    /// нет, и интерфейс обязан обойтись без неё.
    var displayPrice: String? { product?.displayPrice }

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

    /// Загружает товар. Вызывается на старте и повторно на пейволле:
    /// первый вызов мог прийтись на самолётный режим.
    @MainActor
    func load() async {
        if product == nil {
            isLoadingProduct = true
            defer { isLoadingProduct = false }
            do {
                product = try await Product.products(for: [Self.premiumProductID]).first
                lastError = product == nil
                    ? "Товар недоступен в вашем регионе или ещё не одобрен."
                    : nil
            } catch {
                lastError = "Не удалось загрузить цену. Проверьте соединение."
            }
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
